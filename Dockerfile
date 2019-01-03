
FROM ubuntu:18.04

# --->
# ---> Install openssl for creating the on-premises Root CA and
# ---> also install the AWS Cli for accessing AWS's Cert Manager
# ---> API to create and use the subordinate cloud-centric CA.
# --->

USER root
RUN apt-get update && apt-get --assume-yes upgrade && apt-get --assume-yes install -qq -o=Dpkg::Use-Pty=0 \
    python3-pip \
    jq          \
    groff       \
    openssl

RUN pip3 install --upgrade awscli && pip3 --version && aws --version

# --->
# ---> Create 2 directories where the first contains the script
# ---> and other scaffolding artifacts and the second contains
# ---> the key and certificate artifacts.
# --->

RUN mkdir -p /root/cert.authority /root/cert.directory
RUN chmod 700 /root/cert.directory
WORKDIR /root/cert.authority

# --->
# ---> Install the key artifacts from the docker context
# ---> into the staging folder /root/cert.authority
# --->

COPY cert-authority-manager.sh .
COPY openssl-directives.cnf .
COPY subordinate-ca-template.json .

RUN chmod u+x cert-authority-manager.sh
RUN touch index.txt && echo 1000 > serial


# --->
# ---> docker run invokes the cert authority manager
# --->

ENTRYPOINT ["/root/cert.authority/cert-authority-manager.sh"]
