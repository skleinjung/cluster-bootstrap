FROM lachlanevenson/k8s-kubectl:v1.12.8 as kubectl
FROM alpine:3.8

COPY --from=kubectl /usr/local/bin/kubectl /usr/local/bin/kubectl

RUN apk add --no-cache curl bash openssl

RUN curl -o /bin/get_helm.sh -L https://git.io/get_helm.sh; \
    chmod 700 /bin/get_helm.sh

COPY openssl.cnf /tmp/openssl.cnf
COPY docker-entrypoint.sh /bin/docker-entrypoint.sh
RUN chmod 700 /bin/docker-entrypoint.sh; \
    dos2unix /bin/docker-entrypoint.sh; \
    cat /tmp/openssl.cnf >> /etc/ssl/openssl.cnf; \
    rm /tmp/openssl.cnf

ENV HELM_VERSION=""

ENTRYPOINT [ "/bin/docker-entrypoint.sh" ]