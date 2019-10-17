#!/bin/bash

# https://labs.consol.de/devops/2019/07/31/installing-gitlab-on-openshift.html

export NAMESPACE=gitlab

oc new-project ${NAMESPACE}
oc adm policy add-scc-to-user anyuid -z default -n ${NAMESPACE}
oc adm policy add-scc-to-user anyuid -z gitlab-runner -n ${NAMESPACE}
oc adm policy add-scc-to-user anyuid -z gitlab-shared-secrets -n ${NAMESPACE}
oc adm policy add-scc-to-user anyuid -z gitlab-gitlab-runner -n ${NAMESPACE}
oc adm policy add-scc-to-user anyuid -z gitlab-prometheus-server -n ${NAMESPACE}

# Get the TLS certs
oc get -n default secret router-certs -o jsonpath='{.data.tls\.crt}' | base64 -d > tls.crt
oc get -n default secret router-certs -o jsonpath='{.data.tls\.key}' | base64 -d > tls.key

# Bug https://gitlab.com/charts/gitlab/issues/1192
oc adm policy add-scc-to-group anyuid system:authenticated -n ${NAMESPACE}

# rbac-config defaults to using the kube-system namespace so we have to use sed first
wget  https://gitlab.com/charts/gitlab/raw/master/doc/installation/examples/rbac-config.yaml
sed -i "s/kube-system/${NAMESPACE}/g" ./rbac-config.yaml
oc create -f ./rbac-config.yaml

wget https://storage.googleapis.com/kubernetes-helm/helm-v2.14.1-linux-amd64.tar.gz
tar -xzf helm-v2.14.1-linux-amd64.tar.gz
pushd linux-amd64

./helm init --override 'spec.template.spec.containers[0].command'='{/tiller,--storage=secret,--listen=localhost:44134}' --service-account=tiller --tiller-namespace=${NAMESPACE}


./helm repo add gitlab https://charts.gitlab.io/
./helm repo update

./helm upgrade --tiller-namespace=${NAMESPACE} -f ../gitlab-values.yml --install gitlab gitlab/gitlab \
  --timeout 600 \
  --version 2.1.1 \
  --set nginx-ingress.enabled=false \
  --set global.hosts.domain=apps.dan.redhatgov.io \
  --set global.hosts.externalIP=34.196.29.195 \
  --set certmanager-issuer.email=danclark@redhat.com \
  --set global.edition=ce \
  --set certmanager.install=false \
  --set global.ingress.configureCertmanager=false \
  --set gitlab-runner.install=false \
  --set certmanager.rbac.create=false \
  --set nginx-ingress.rbac.createRole=false \
  --set prometheus.rbac.create=false \
  --set gitlab-runner.rbac.create=false
  # External object storage
  #--set global.minio.enabled=false \
  # At some point I'll have to follow:
  # https://docs.gitlab.com/charts/advanced/external-object-storage/index.html
  # TLS options (for now use self signed)
  # At some point I'll test it with an external postgres repo
  # made with the chruncy operator
  #--set postgresql.install=false \
  #--set global.psql.host=production.postgress.hostname.local \
  #--set global.psql.password.secret=kubernetes_secret_name \
  #--set global.psql.password.key=key_that_contains_postgres_password \
  # Configure community edition instead of enterprise

popd
