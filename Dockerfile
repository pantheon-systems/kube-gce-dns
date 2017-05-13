FROM scratch

COPY ca-certificates.crt /etc/ssl/certs/
COPY ./kube-gce-dns /

ENTRYPOINT ["/kube-gce-dns server"]
