# k8s-bluegreen-deployment-demo
The purpose of this project is to explore blue green deployments in Kubernetes with Minikube.  This work is based on Ian Lewis' [Kubernetes Blue/Green Deployment Tutorial](https://github.com/ianlewis/kubernetes-bluegreen-deployment-tutorial), but utilizes a local Minikube cluster instead of GCP.


## Prerequisites
- [minikube](https://github.com/kubernetes/minikube)
- [kubectl](https://github.com/kubernetes/kubectl)
- I personally alias kubectl to k so all references to k will mean kubectl if you don't have that aliased
    - if you want to alias it like I do for convenience,
    - ```alias k="kubectl"```

if you are on a mac and using brew for package management you can use the command below to install both minikube and kubectl

```brew cask install mikube kubectl```

## Initializing a local Kubernetes cluster with Minikube
As crazy as it sounds, all we need to do to set up a local kubernetes cluster with minikube is type one command.

```minikube start```

When this is done we'll have a basic kubernetes environment that we can begin doing all sorts of interesting things on.

## Creating the Blue Deployment
The blue deployment represents the code that is currently live in production.  It can be accessed by users because it is exposed by a Kubernetes Service with type LoadBalancer.

#### hack/k8s/blue-deployment.yaml
```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nginx-1.14
spec:
  replicas: 3
  template:
    metadata:
      labels:
        name: nginx
        version: "1.14"
    spec:
      containers: 
        - name: nginx
          image: nginx:1.14
          ports:
            - name: http
              containerPort: 80
```

Let's create our Blue Deployment:

```k apply -f hack/k8s/blue-deployment.yaml```

Now if we run

``` k get pods --watch```

We should see 3 nginx 1.14 pods spinning up.  Wait for them to become ready.  You can use the --watch argument of kubectl to monitor the status of your pods in realtime.

## Exposing our Blue Deployment via a Service
The ```name``` and ```version``` labels specified in the Deployment are used to select pods for the service to route traffic to.

#### hack/k8s/service-blue.yaml
```yaml
apiVersion: v1
kind: Service
metadata: 
  name: nginx
  labels: 
    name: nginx
spec:
  ports:
    - name: http
      port: 80
      targetPort: 80
  selector: 
    name: nginx
    version: "1.14"
  type: LoadBalancer
```

Let's create our Service:

```k apply -f hack/k8s/service-blue.yaml```

We'll watch our service the same way we watched out deployments so that we know when we're ready to move on

``` k get services --watch ```

In order to test our service, minikube offers a nifty feature to peak inside our cluster and check out a service quickly with the service command.  Let's load up our newly deployed nginx deployment in a browser to check it out.

``` minikube service nginx ```

This command will be open our nginx service in a browser window for us by querying the kubernetes api for us via minikube.  We'll use this same command with --url flag to give us the url programatically later on.

### Testing the Blue Deployment
We can test our blue deployment by polling the server and grabbing the deployed version of NGINX.

```
./hack/sh/test.sh
```

All this simple bash script does is get our service's url from our kubernetes cluster using minikube.  We store this in a variable called server and curl every half second the version displayed on nginx's ```/version``` page.  

#### hack/sh/test.sh
```
server=$(minikube service nginx --url)
while true; do curl --insecure $server/version | grep nginx; sleep 0.5; done
```


We should be able to see that our current deployment shows an nginx version of 1.14.

## Updating our application
Here, we will create a new Deployment to update the application.  The servie will be updated to point at our new version.

### Creating the Green Deployment
Our Green Deployment will be a new deployment created with different labels.  Since our new labels will not match the ones of our Service, no requests will be sent to the pods in the Green Deployment currently.

#### hack/k8s/green-deployment.yaml
```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nginx-1.15
spec:
  replicas: 3
  template:
    metadata:
      labels:
        name: nginx
        version: "1.15"
    spec:
      containers: 
        - name: nginx
          image: nginx:1.15
          ports:
            - name: http
              containerPort: 80
```

Let's create our Green Deployment:

```k apply -f hack/k8s/green-deployment.yaml```

Let's once again watch to see when our Green Deployment Pods will be ready

```k get pods --watch```

When they are ready, we can move on to updating our service to point to the green deployment.

### Routing Traffic to Green
In order to route traffic to our green deployment, we must modify our service to select pods from the green deployment.  The service will then route new traffic to our green deployment's pods.

Let's update our Service:

```k apply -f hack/k8s/service-green.yaml ```

### Testing that Traffic is going to Green
Let's test with the same script we used before to check the version of NGINX our application is currently running and know that we've successfully switched traffic from our old blue deployment to our new green deployment.

```./hack/sh/test.sh ```


## Automating Blue/Green Deployments
You could theoretically implement Blue/Green deployments as a type of Custom Resource Definition in Kubernetes.  This is probably the preferable way to do it.  However, you can also do it with this bash script.  The script creates a new Deployment and waits for it to become ready prior to updating Service's selector.

```
#!/bin/bash

# bg-deploy.sh <servicename> <version> <green-deployment.yaml>
# Deployment name should be <service>-<version>

DEPLOYMENTNAME=$1-$2
SERVICE=$1
VERSION=$2
DEPLOYMENTFILE=$3

kubectl apply -f $DEPLOYMENTFILE

# Wait until the Deployment is ready by checking the MinimumReplicasAvailable condition.
READY=$(kubectl get deploy $DEPLOYMENTNAME -o json | jq '.status.conditions[] | select(.reason == "MinimumReplicasAvailable") | .status' | tr -d '"')
while [[ "$READY" != "True" ]]; do
    READY=$(kubectl get deploy $DEPLOYMENTNAME -o json | jq '.status.conditions[] | select(.reason == "MinimumReplicasAvailable") | .status' | tr -d '"')
    sleep 5
done

# Update the service selector with the new version
kubectl patch svc $SERVICE -p "{\"spec\":{\"selector\": {\"name\": \"${SERVICE}\", \"version\": \"${VERSION}\"}}}"

echo "Done."
```

## Credits
Thanks to Ian Lewis of Google Cloud Platform for intiially publishing similar content for GCP [here](https://github.com/ianlewis/kubernetes-bluegreen-deployment-tutorial) under the Apache License.
