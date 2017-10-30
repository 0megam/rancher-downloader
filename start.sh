#!/bin/bash
targetRegistry="$1"
extra_images=(rancher/server:v1.6.10 \
	      rancher/agent:v1.2.6 \
              rancher/lb-service-haproxy:v0.7.9 \
              gcr.io/google_containers/pause-amd64:3.0)
catalog_dir="rancher-catalog"
rancher_k8s_dir="kubernetes-package"
rancher_k8s_branch="origin/k8s-v1.7"
#rancher_k8s_branch="origin/v1.6"
subcatalog_dir="infra-templates"
rancher_catalog_url="https://github.com/rancher/rancher-catalog"
rancher_k8s_url="https://github.com/rancher/kubernetes-package"
git clone ${rancher_catalog_url} ${catalog_dir}
git clone ${rancher_k8s_url} ${rancher_k8s_dir} 
IFS=$'\n' read -ra branches <<<$(git -C ${catalog_dir} branch -r | sed 's/origin\/HEAD -> //g')
options=()
for branch in ${branches[@]}; do
    options+=($branch "-" off)
done
echo ${options[@]}


choice=$(dialog --ok-label "Next" --radiolist "Select rancher-catalog branch:" 50 100 50 ${options[@]} 2>&1 >/dev/tty)
echo $choice
git -C ${catalog_dir} checkout ${choice/origin\//}
git -C ${catalog_dir} pull origin ${choice/origin\//}
git -C ${catalog_dir} reset --hard HEAD

git -C ${rancher_k8s_dir} checkout ${rancher_k8s_branch/origin\//}
git -C ${rancher_k8s_dir} pull origin ${rancher_k8s_branch/origin\//}
git -C ${rancher_k8s_dir} reset --hard HEAD

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
cd -
images+=($(grep -r 'image: ' ${rancher_k8s_dir}/addon-templates/ | sed 's/.*$GCR_IO_REGISTRY\/\($BASE_IMAGE_NAMESPACE\|google_containers\).*\/\(.*\)/gcr.io\/google_containers\/\2/;
                                                                        s/.*$GCR_IO_REGISTRY\/\($HELM_IMAGE_NAMESPACE\|kubernetes-helm\).*\/\(.*\)/gcr.io\/kubernetes-helm\/\2/;
                                                                        s/"//g'))
images+=("${extra_images[@]}")
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
mkdir images
for image in ${images_to_download[@]}; do
    docker pull $image
    if [[ "${targetRegistry}" ]]; then
        docker tag $image "${targetRegistry}/${image}"
        SAVE_LIST="${SAVE_LIST} ${targetRegistry}/${image}"
    fi
    echo Done.
done
if [[ "${targetRegistry}" ]]; then
    docker save ${SAVE_LIST} | pigz -p 3 | pv > images/rancher_images.tar.gz
else
    docker save ${images_to_download[@]} | pigz -p 3 | pv > images/rancher_images.tar.gz
fi
