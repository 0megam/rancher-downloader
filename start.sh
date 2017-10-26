#!/bin/bash
images_to_download=(rancher/server:v1.6.10 \
		    rancher/agent:v1.2.6 \
                    rancher/lb-service-haproxy:v0.7.9 \
                    gcr.io/google_containers/pause-amd64:3.0
		    gcr.io/google_containers/kubernetes-dashboard-amd64:v1.6.1
                    gcr.io/google_containers/k8s-dns-kube-dns-amd64:1.14.2
                    gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64:1.14.2
                    gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.2
                    gcr.io/google_containers/heapster-influxdb-amd64:v1.1.1
                    gcr.io/google_containers/heapster-grafana-amd64:v4.0.2
                    gcr.io/google_containers/heapster-amd64:v1.3.0-beta.1
                    gcr.io/kubernetes-helm/tiller:v2.3.0)
catalog_dir="rancher-catalog"
subcatalog_dir="infra-templates"
rancher_catalog_url="https://github.com/rancher/rancher-catalog"
git clone ${rancher_catalog_url} ${catalog_dir}
IFS=$'\n' read -ra branches <<<$(git -C ${catalog_dir} branch -r | sed 's/origin\/HEAD -> //g')
options=()
for branch in ${branches[@]}; do
    options+=($branch "-" off)
done
echo ${options[@]}
#exit 0
choice=$(dialog --ok-label "Next" --radiolist "Select rancher-catalog branch:" 50 100 50 ${options[@]} 2>&1 >/dev/tty)
git -C ${catalog_dir} checkout ${choice}
git -C ${catalog_dir} pull ${choice//// }
git -C ${catalog_dir} reset --hard HEAD

cd ${catalog_dir}/${subcatalog_dir}
options=()
images=()
for dir in $(ls -d */); do
    for vers in $(ls -d $dir*/ | sort --version-sort); do
        minver=$(sed -n 's/^.*minimum_rancher_version: \([.0-9a-z-]*\).*$/\1/p' $vers/rancher-compose.yml | tr -d '[:space:]')
        maxver=$(sed -n 's/^.*maximum_rancher_version: \([.0-9a-z-]*\).*$/\1/p' $vers/rancher-compose.yml | tr -d '[:space:]')
        versions="${minver:=notfound}-${maxver:=notfound}"
        options+=("$vers" "$versions" off)
    done
done
choices=$(dialog --separate-output --ok-label "Next" --checklist "Select services:" 50 100 50 ${options[@]} 2>&1 >/dev/tty)
if [ -z "${choices[@]}" ]; then
    echo "You have to choose something... Exiting.."
    exit 1
fi
echo ${choices[@]}
for choice in $choices; do
    echo "inside"
    images+=($(grep -hor --exclude="*.md" -e "rancher\/[\.0-9a-z-]\+:[\.0-9a-z-]\+" $choice | grep -v "shared"))
done

options=()
i=1
for image in $(echo "${images[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '); do
    options+=("$image" download on) 
    ((i++)) 
done
choices=$(dialog --separate-output --ok-label "Download" --checklist "Select images for download:" 50 100 50 ${options[@]} 2>&1 >/dev/tty)
for choice in $choices; do
    images_to_download+=($choice)
done
echo ${images_to_download[@]}
cd -
mkdir images
for image in ${images_to_download[@]}; do
        docker pull $image
        echo Done.
done
echo ${images_to_download[@]}
docker save ${images_to_download[@]} | pigz -p 3 | pv > images/rancher_images.tar.gz

