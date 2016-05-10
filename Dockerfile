FROM scratch
ADD ca-certificates.crt /etc/ssl/certs/
ADD ./kube-gce-dns /

CMD /kube-gce-dns server
