server=$(minikube service nginx --url)
while true; do curl --insecure $server/version | grep nginx; sleep 0.5; done