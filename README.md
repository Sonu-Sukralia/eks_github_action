# EKS GitHub Action

Deploy a containerised web app to **Amazon EKS** with **GitHub Actions** and **Terraform**. The cluster runs 2 nodes and 2 pods, and it recovers on its own when a pod or node fails.

![AWS](https://img.shields.io/badge/AWS-EKS-orange)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED)

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Deployment](#deployment)
- [Testing Self-Healing](#testing-self-healing)
- [Updating the Website](#updating-the-website)
- [Cleanup](#cleanup)
- [Cost](#cost)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This project is the EKS version of an earlier EC2-based deployment. It adds an EKS setup next to the existing one. Nothing in `terraform/`, `app/` or the old workflows is changed.

## Architecture

```
GitHub Actions
  1. Build image        -> Docker Hub
  2. Terraform          -> VPC (2 AZs) + EKS cluster + node group (min 2 nodes)
  3. kubectl apply      -> Deployment (2 pods) + Service (AWS load balancer) + PodDisruptionBudget
```

| Goal                          | How it is done                                                                                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Minimum 2 nodes               | `min_size = 2`, `desired_size = 2` in `eks/terraform/eks.tf`, with nodes spread across 2 Availability Zones                                            |
| 2 pods                        | `replicas: 2` in `eks/k8s/deployment.yaml`, spread across nodes with `topologySpreadConstraints`                                                       |
| Pod fails, new one is created | The Deployment's ReplicaSet always keeps 2 pods. A liveness probe restarts a stuck container, and a readiness probe keeps traffic away from unhealthy pods |
| No downtime on deploy         | `maxUnavailable: 0` rolling update and a PodDisruptionBudget (`minAvailable: 1`)                                                                       |

## Features

- Infrastructure as code with Terraform (VPC, EKS cluster, managed node group)
- Fully automated CI/CD with GitHub Actions
- High availability across 2 Availability Zones
- Self-healing pods and nodes
- Zero-downtime rolling updates
- One-click destroy workflow to avoid surprise AWS bills

## Project Structure

```
.
├── .github/
│   └── workflows/
│       ├── deploy-eks.yml          # Build image, create infra, deploy app
│       ├── destroy-eks.yml         # Tear down everything
│       └── test-self-healing.yml   # Delete a pod and verify recovery
├── app/                            # Web application (index.html, Dockerfile)
├── eks/
│   ├── terraform/                  # VPC, EKS cluster, node group
│   ├── k8s/                        # Deployment, Service, PodDisruptionBudget
│   └── iam-policy.json             # Extra IAM permissions needed for EKS
└── README.md
```

## Prerequisites

- An AWS account
- An IAM user (`github-actions`) with access keys
- A Docker Hub account and a **public** repository for the image
- A GitHub repository with Actions enabled
- Optional, for local testing: [AWS CLI](https://aws.amazon.com/cli/) and [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Setup

1. **IAM permissions.** The existing user only has EC2 and S3 access. EKS also needs EKS and IAM role permissions.
   In IAM, open the `github-actions` user, then **Add permissions → Create inline policy → JSON**, and paste the contents of `eks/iam-policy.json`.
   For a quick learning setup you can attach `AdministratorAccess` instead. Remove it afterwards.

2. **Repository secrets.** Add these under **Settings → Secrets and variables → Actions**. The same five secrets are reused from the EC2 setup, so nothing new is needed if you already have them.

   | Secret                  | Description              |
   | ----------------------- | ------------------------ |
   | `AWS_ACCESS_KEY_ID`     | IAM user access key      |
   | `AWS_SECRET_ACCESS_KEY` | IAM user secret key      |
   | `DOCKERHUB_USERNAME`    | Docker Hub username      |
   | `DOCKERHUB_TOKEN`       | Docker Hub access token  |
   | *(fifth secret)*        | Check your workflow files for the exact name |

   > Update this table so the names match the ones used in your workflow files.

3. **Region.** The default is `ap-southeast-2`. If you change it, update it in `deploy-eks.yml`, `destroy-eks.yml`, `test-self-healing.yml` and `eks/terraform/variables.tf`.

4. **Old EC2 deploy (optional).** To stop a push from also creating the EC2 server, go to **Actions → Build and Deploy → ⋯ → Disable workflow**.

## Deployment

1. Go to **Actions → Build and Deploy to EKS → Run workflow**.
2. Wait about 12–18 minutes. Most of this time is spent creating the cluster and nodes.
3. Open the run **Summary** to find the app URL (a load balancer DNS name), the 2 nodes and the 2 pods.
4. Open the URL with `http://`. The load balancer can take 2–3 minutes to start answering.

## Testing Self-Healing

### Option A: From GitHub

Go to **Actions → Test EKS Self-Healing → Run workflow**.

The workflow deletes one pod while sending requests to the site, then shows that a new pod replaced it. All HTTP codes during replacement should be `200`, because the other pod keeps serving.

### Option B: From your own computer

```bash
aws eks update-kubeconfig --name demo-app-eks --region ap-southeast-2

kubectl get nodes                # expect 2 nodes, Ready
kubectl get pods -o wide         # expect 2 pods, usually on different nodes

# Terminal 1: watch live
kubectl get pods -w

# Terminal 2: kill one pod
kubectl delete pod <pod-name>
```

In terminal 1 you will see the old pod go `Terminating` and a new pod appear (`ContainerCreating` → `Running`) within seconds. The pod count returns to 2.

### Option C: Kill a whole node (harder test)

```bash
aws ec2 terminate-instances --instance-ids <one-node-instance-id>
kubectl get nodes -w
```

The node group's Auto Scaling Group starts a replacement node because `min_size = 2`. Pods on the lost node are rescheduled. This takes a few minutes, and the site stays up on the other node.

## Updating the Website

1. Edit `app/index.html`.
2. Commit and push.
3. Run **Build and Deploy to EKS** again.

The Deployment does a rolling update: a new pod starts and becomes Ready, then an old pod stops. Users see no downtime, and the URL stays the same.

## Cleanup

> **EKS is not cheap. Destroy the environment when you finish.**

Go to **Actions → Destroy EKS Infrastructure → Run workflow**.

It deletes the Kubernetes Service first so the AWS load balancer is removed, then runs `terraform destroy`. Afterwards, check in the AWS console that these are empty:

- **EKS → Clusters**
- **EC2 → Instances**
- **EC2 → Load Balancers**

## Cost

Approximate, so check AWS pricing for your region:

- EKS control plane: about $0.10/hour
- 2 × `t3.small` nodes
- 1 load balancer
- Public IPv4 addresses

Running it for a day costs a few dollars.

## Troubleshooting

| Problem                                              | Cause and fix                                                                                              |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `AccessDenied` on `eks:` or `iam:` actions           | The IAM user is missing the EKS policy. Add `eks/iam-policy.json`.                                         |
| `kubectl` says `You must be logged in to the server` | Run kubectl with the same IAM user that created the cluster, or add your own user under **EKS → Access**.  |
| Pods stuck `Pending`                                 | Not enough room on the nodes. Do not use `t3.micro`. Run `kubectl describe pod <name>`.                    |
| `ImagePullBackOff`                                   | The Docker Hub repository is not public, or the image tag does not exist.                                  |
| Load balancer URL does not open                      | Wait 2–3 minutes. Check `kubectl get svc demo-app`.                                                        |
| Destroy fails on VPC or subnets                      | A load balancer is still alive. Delete it in **EC2 → Load Balancers**, then re-run destroy.                |

## Contributing

1. Fork the repository
2. Create a branch: `git checkout -b feature/my-change`
3. Commit your changes: `git commit -m "Describe your change"`
4. Push the branch: `git push origin feature/my-change`
5. Open a pull request

## License

Add a license file (for example [MIT](https://choosealicense.com/licenses/mit/)) and name it here.

## Author

[Sonu Sukralia](https://github.com/Sonu-Sukralia)
