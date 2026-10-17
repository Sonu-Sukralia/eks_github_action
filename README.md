# Run the same app on Amazon EKS (2 nodes, 2 pods, self-healing)

This adds an EKS version next to the existing EC2 version. Nothing in `terraform/`, `app/` or the old workflows is changed.

## Architecture

```
GitHub Actions
  1. build image -> Docker Hub
  2. Terraform -> VPC (2 AZs) + EKS cluster + node group (min 2 nodes)
  3. kubectl apply -> Deployment (2 pods) + Service (AWS load balancer) + PodDisruptionBudget
```

| Goal | How it is done |
|---|---|
| Minimum 2 nodes | `min_size = 2`, `desired_size = 2` in `eks/terraform/eks.tf`, nodes spread across 2 Availability Zones |
| 2 pods | `replicas: 2` in `eks/k8s/deployment.yaml`, spread across nodes with `topologySpreadConstraints` |
| Pod fails, new one is created | The Deployment's ReplicaSet always keeps 2 pods. A liveness probe restarts a stuck container, a readiness probe keeps traffic away from unhealthy pods |
| No downtime on deploy | `maxUnavailable: 0` rolling update and a PodDisruptionBudget (`minAvailable: 1`) |

## Files to add to your repo

```
.github/workflows/deploy-eks.yml
.github/workflows/destroy-eks.yml
.github/workflows/test-self-healing.yml
eks/terraform/*.tf
eks/k8s/*.yaml
eks/iam-policy.json
```

## Setup

1. **IAM permissions.** The existing user only has EC2 and S3 access. EKS also needs EKS and IAM role permissions. In IAM, open the `github-actions` user, then **Add permissions -> Create inline policy -> JSON**, and paste `eks/iam-policy.json`. (For a quick learning setup you can attach `AdministratorAccess` instead, then remove it later.)
2. **Secrets.** The same five repository secrets are reused. Nothing new is needed.
3. **Region.** Same as before: `ap-southeast-2` in the three `*-eks.yml` / `test-self-healing.yml` files and in `eks/terraform/variables.tf`.
4. **Old EC2 deploy.** Optionally disable the old workflow so a push doesn't also create the EC2 server: **Actions -> Build and Deploy -> ... -> Disable workflow**.

## Deploy

**Actions -> Build and Deploy to EKS -> Run workflow.** It takes about 12-18 minutes, mostly creating the cluster and nodes.

When it finishes, the run **Summary** shows the app URL (a load balancer DNS name), the 2 nodes and the 2 pods. Open it with `http://`. The load balancer can take 2-3 minutes to start answering.

## Test self-healing

### Option A: from GitHub
**Actions -> Test EKS Self-Healing -> Run workflow.** It deletes one pod while sending requests to the site, then shows that a new pod replaced it. The HTTP codes during replacement should all be `200`, because the other pod keeps serving.

### Option B: from your own computer
```bash
aws eks update-kubeconfig --name demo-app-eks --region ap-southeast-2

kubectl get nodes                         # expect 2 nodes, Ready
kubectl get pods -o wide                  # expect 2 pods, usually on different nodes

# Terminal 1: watch live
kubectl get pods -w

# Terminal 2: kill one pod
kubectl delete pod <pod-name>
```
In terminal 1 you will see the old pod go `Terminating` and a new pod appear (`ContainerCreating` -> `Running`) within seconds. The pod count returns to 2.

### Option C: kill a whole node (harder test)
```bash
aws ec2 terminate-instances --instance-ids <one-node-instance-id>
kubectl get nodes -w
```
The node group's Auto Scaling Group starts a replacement node because `min_size = 2`. Pods on the lost node are rescheduled. This takes a few minutes, and the site stays up on the other node.

## Update the website

Edit `app/index.html`, push, then run **Build and Deploy to EKS** again. The Deployment does a rolling update: a new pod starts, becomes Ready, then an old pod stops. Users see no downtime, and the URL stays the same.

## Clean up (important: EKS is not cheap)

**Actions -> Destroy EKS Infrastructure -> Run workflow.**

It deletes the Kubernetes Service first so the AWS load balancer is removed, then runs `terraform destroy`. Afterwards check in the AWS console that **EKS -> Clusters**, **EC2 -> Instances** and **EC2 -> Load Balancers** are empty.

## Cost

Roughly (check AWS pricing for your region): EKS control plane about $0.10/hour, 2 x `t3.small` nodes, 1 load balancer, and public IPv4 addresses. Running it for a day costs a few dollars. Destroy it when you finish.

## Troubleshooting

| Problem | Cause and fix |
|---|---|
| `AccessDenied` on `eks:` or `iam:` actions | The IAM user is missing the EKS policy. Add `eks/iam-policy.json`. |
| `kubectl` says `You must be logged in to the server` | Run kubectl with the same IAM user that created the cluster, or add your own user under **EKS -> Access**. |
| Pods stuck `Pending` | Not enough room on the nodes. Do not use `t3.micro`. Run `kubectl describe pod <name>`. |
| `ImagePullBackOff` | The Docker Hub repository is not public, or the image tag does not exist. |
| Load balancer URL does not open | Wait 2-3 minutes. Check `kubectl get svc demo-app`. |
| Destroy fails on VPC or subnets | A load balancer is still alive. Delete it in **EC2 -> Load Balancers**, then re-run destroy. |
