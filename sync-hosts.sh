#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ORIGIN="origin"
WORKDIR="workdir"
OUTPUT=${OUTPUT:-hosts}
DNS=${DNS:-}
DOMAINS=${DOMAINS:-}
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SOURCE=$(git config remote.origin.url)
REF_SOURCE="${SOURCE}"

if [[ "${DOMAINS}" == "" ]]; then
    echo "DOMAINS is required"
    exit 1
fi

mkdir -p "${WORKDIR}" && cd "${WORKDIR}"

if ! [[ -d .git ]]; then
    git init
fi

if [[ "$(git config user.name)" == "" ]]; then
    git config --global user.name "bot"
fi

if [[ "$(git remote | grep ${ORIGIN})" == "${ORIGIN}" ]]; then
    git remote remove "${ORIGIN}"
fi

if [[ "${GH_TOKEN:-}" != "" ]]; then
    SOURCE=$(echo ${SOURCE} | sed "s#https://github.com#https://bot:${GH_TOKEN}@github.com#g")
fi

git remote add "${ORIGIN}" "${SOURCE}"

git fetch -f "${ORIGIN}" "${BRANCH}" --depth=1 && git checkout -f -B "${BRANCH}" --track "${ORIGIN}/${BRANCH}"

cat <<EOF >${OUTPUT}
# Last Update: $(date +"%Y-%m-%dT%H:%M:%S%z")
# Source: ${REF_SOURCE}

EOF

declare -A mapIpDomains

function get_ip() {
    local domain="$1"
    local dns="${2:-}"
    nslookup "${domain}" ${dns} | grep "Address" | grep -v '#' | awk '{print $2}' | sort
}

for domain in ${DOMAINS[@]}; do
    ips=$(get_ip "${domain}" ${DNS})
    if [[ "${ips}" == "" ]]; then
        echo "# ${domain} not found" >>"${OUTPUT}"
    else
        if [[ $(echo "${ips}" | wc -l) -le 1 ]]; then
            ori="${ips}"
            for _ in {1..10}; do
                for _ in {1..10}; do
                    ip=$(get_ip "${domain}" ${DNS})
                    if [[ "${ip}" == "${ori}" ]]; then
                        break
                    fi
                    ips="${ips}
${ip}"
                done
            done
            ips="$(echo "$ips" | sort | uniq)"
        fi
        for ip in ${ips[@]}; do
            if [[ -v "mapIpDomains[${ip}]" ]]; then
                mapIpDomains[${ip}]="${mapIpDomains[${ip}]} ${domain}"
            else
                mapIpDomains[${ip}]="${domain}"
            fi
        done
    fi
done

for ip in "${!mapIpDomains[@]}"; do
    echo "${ip} ${mapIpDomains[${ip}]}" >>"${OUTPUT}"
done

git add "${OUTPUT}"
git commit -m "Automatic update ${OUTPUT}"
git push "${ORIGIN}" "${BRANCH}"
