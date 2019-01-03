#### Use docker to create an on-premises (root) certificate authority and the AWS Cli (acm-pca) to create a cloud-based subordinate certificate authority in AWS Certificate Manager. The former signs the Cert Signing Request (CSR) of the latter and the signed (and root chain) certificates are imported thus activating the AWS CM cert authority.

---

# On-Premises Root CA | AWS Certificate Manager Subordinate CA

It is **simple and compelling** to issue, renew, revoke and audit certificates with AWS's Certificate Manager and your own **dockerized private certficate authority**. The case for a **cloud-based certificate authority** is even stronger when the majority of your infrastructure resides in the AWS cloud.

## Usage

Put the **AWS credentials** from your password manager into this docker run command. Provide **different common names** for your on-premises and AWS Certificate Manager subordinate CA. Create **an empty directory** and issue this **`docker run`** from within it.

```
docker run                                  \
    --name=certificate.authority            \
    --volume=$PWD:/root/cert.directory      \
    --env ON_PREMISES_CA_CN=devopslab.local \
    --env SUBORDINATE_CA_CN=devopslab.cloud.$(date +"%y%j%H%M") \
    --env ORG_UNIT=Engineering              \
    --env ORG_NAME="DevOps Laboratory"      \
    --env LOCALITY=London                   \
    --env PROVINCE=England                  \
    --env COUNTRY_CODE=GB                   \
    --env AWS_ACCESS_KEY_ID=$(safe print @access.key)     \
    --env AWS_SECRET_ACCESS_KEY=$(safe print @secret.key) \
    --env AWS_DEFAULT_REGION=$(safe print region.key)     \
    devops4me/cert-authority ;
```
## input | certificate authority subject fields

Aside from the 3 AWS IAM user credentials you need to input 7 data points. The common names of both authorities and the five (and only five) subject fields.

|  #  | Subject Field     | ID  | AWS Subordinate CA  | On-Premises Root CA |
|:---:|:----------------- |:---:|:------------------- |:------------------- |
|  1  | Country Code      | C   | GB                  | GB                  |
|  2  | State (Province)  | ST  | England             | England             |
|  3  | Locality          | L   | London              | London              |
|  4  | Organization      | O   | DevOps Laboratory   | DevOps Laboratory   |
|  5  | Organization Unit | OU  | Engineering         | Engineering         |
|  6  | **Common Name**   | CN  | **devopslab.cloud** | **devopslab.local** |


## output | on-premises private key and certificate

Your empty directory is no longer empty. It holds four files in pem format which are

1. a **8,192 bit private key** for the *on-premises (root) certificate authority*
1. a *self-signed certificate* for the **on-premises (root) certificate authority**
1. a **downloaded certificate signing request (CSR)** for the *AWS CM (subordinae) CA*
1. a **signed certificate** for the *AWS Certificate Manager (subordinae) CA*

Discard the latter two certificates but call up your **password/credentials manager** and place into it the **private key and certificate** for the on-premises (root) certificate authority. You will need these later to sign the CSRs of other intermediate/subordinate CAs.


---


## [cert-authority-manager.sh script](https://github.com/devops4me/docker-certificate-authority-manager/blob/master/cert-authority-manager.sh) | [Docker](https://github.com/devops4me/docker-certificate-authority-manager/blob/master/Dockerfile)

The **[cert-authority-manager.sh script](https://github.com/devops4me/docker-certificate-authority-manager/blob/master/cert-authority-manager.sh)** does most of the legwork and it runs within a [docker container](https://cloud.docker.com/repository/registry-1.docker.io/devops4me/cert-authority). The **[Dockerfile](https://github.com/devops4me/docker-certificate-authority-manager/blob/master/Dockerfile)** ensures that openssl and the most up-to-date  AWS Cli (with the acm-pca command) is installed.


---

## the road to on-premises and cloud-based private certificate authorities

Our journey will create a subordinate CA in AWS, a Root CA in Docker and a private domain in Route53. We will then issue certificates to be served up by load-balancers and on the opposite side we'll instruct our operating system and browsers to trust it. The 10 steps enable us to


### Why use Docker?

***You don't want to (and shouldn't) create a Root CA on your laptop.*** As your (pet) laptop evolves the dependencies on **OpenSSL**, **Linux** and the AWS Cli will destabilize this important area. A cattle-like Docker container is much more suitable especially when you begin to work with **multiple certificate authorities**.


### Creating an AWS Certificate Manager Subordinate Cert Authority

The 5 subject fields in the on-premises Root CA must match those in AWS Certificate Manager CA. The script inserts the parameter subject fields into the **[subordinate-ca-template.json](https://github.com/devops4me/docker-certificate-authority-manager/blob/master/subordinate-ca-template.json)** and then the same in the openssl root CA creation command.

```bash
aws acm-pca create-certificate-authority \
    --certificate-authority-configuration file://$PWD/subordinate-ca-config.json \
    --certificate-authority-type "SUBORDINATE" \
    --idempotency-token $(date +"%y%j%H%M")
```

The ***`aws acm-pca wait`*** command is used with the **`certificate-authority-csr-created`** flag so that we do not try to download the certificate signing request (CSR) before it is ready.

### Creating an On-Premises Root Certificate Authority

We create an **8,192 bit private key** for our on-premises root CA and use that to create a self-signed certificate. The **[openssl-directives.cnf](https://github.com/devops4me/docker-certificate-authority-manager/blob/master/openssl-directives.cnf)** configures the certificate creation and signing steps.

```bash
openssl genrsa -out /root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-key.pem 8192
chmod 400 /root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-key.pem

openssl req            \
    -key /root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-key.pem  \
    -out /root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-cert.pem \
    -new               \
    -x509              \
    -days 7300         \
    -sha256            \
     -extensions v3_ca \
    -config openssl-directives.cnf \
    -subj "/C=$COUNTRY_CODE/ST=$PROVINCE/L=$LOCALITY/O=$ORG_NAME/OU=$ORG_UNIT/CN=$ON_PREMISES_CA_CN" ;
```

### Signing the Subordinate CA's CSR

Unknown to you, Certificate Manager creates a private key and stores it in KMS (Key Management Service). It uses the private key to issue a certificate signing request (CSR) for the on-premises root certificate authority to sign.

```bash
openssl ca     \
    -config openssl-directives.cnf \
    -extensions v3_intermediate_ca \
    -outdir /root/cert.directory   \
    -days 3650 \
    -notext    \
    -batch     \
    -md sha256 \
    -keyfile /root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-key.pem  \
    -cert    /root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-cert.pem \
    -in      /root/cert.directory/$SUBORDINATE_CA_CN-subordinate-ca-csr.pem  \
    -out     /root/cert.directory/$SUBORDINATE_CA_CN-subordinate-ca-cert.pem ;
```

This command in the script signs the CSR and outputs a certificate for your AWS subordinate CA.


### Importing the Signed Certificate and the CA's Chain Certs

In our case the **chain of trust** is only one deep so the import command effectively sends back just two certificates

- the signed subordinate CA's certificate
- the on-premises (trust chain) Root CA's certificate

```bash
aws acm-pca import-certificate-authority-certificate \
    --certificate-authority-arn $SUBORDINATE_CA_ARN  \
    --certificate       file:///root/cert.directory/$SUBORDINATE_CA_CN-subordinate-ca-cert.pem \
    --certificate-chain file:///root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-cert.pem
```

After importing these certificates your subordinate CA's state switches from **`PENDING_CERTIFICATE`** to **`ACTIVE`**.


---


## Gotchas | Importing Signed Certificates back into AWS CM

### Certificate Subject Field Lessons

The 3 hardest learnt lessons the AWS documentation **does not mention** are that

1. **5 of the 6 subject fields must perfectly match** in three (3) places
2. the 6th **common name field must differ** between certificate manager and the root CA
3. the **email address field must be deleted** from the root CA

The root CA certificate will by default contain the email address field which certificate manager currently does not have. Even an empty value in the root CA's email field is deemed as a mismatch by the overly sensitive (underly documented) Certificate Manager.

#### CertificateMismatchException The certificate version must be greater than or equal to 3

You avoid the dreaded **`Certificate Subject Mismatch Exception`** and many hours debugging various oddities in OpenSL and AWS CM by using the docker run command above. 


## OpenSSL failed to Update Database Error

## The Comman Name Field

The **`failed to update database`** error occurs when the common name in the AWS subordinate certificate authority (in AWS CM) is the same as the common name of your Root Certificate Authority.

```
failed to update database
TXT_DB error number 2
```

This error happens when signing the subordinate's CSR (certificate signing request).


---


## Summary | Private Certificate Authority Tools

With your certificate authorities up and running you can step back and make this observation.

#### An ***offline root CA** is **trusting** a cloud based **subordinate CA** to issue, renew, revoke and audit SSL certificates for a private **Route53 (hosted zone)** domain.

Furthermore, humans (via web browsers) and machines in our **intranet and extranet domains**, have been authorized to trust and connect to services presenting the aforementioned unrevoked certificates.


---


## The Next Steps | Issue, Renew and Revoke

What happens after your on-premises CA has been setup and your AWS Certificate Manager CA in an Active state? The next steps are to

1. create a Route53 hosted zone and private domain names
1. get the subordinate CA to issue an SSL certificate for your private domain name
1. configure a load balancer to serve the SSL certificate issued and held in CM
1. configure client operating systems and browsers to trust the certificate
1. issue certificates for intra-cluster and extra-cluster communications
1. revoke certificates with an S3 Bucket used by Certificate Manager to manage state

### Automated Certificate Renewal

The **key value-add** gained from using Certificate Manager is ***automated certificate renewal*** and this benefit comes, **and grows** with time.

Watch others sweat while they manually renew and re-issue dozens of certificates every year, from both public and private certificate authorities.

Your subordinate **cloud-based certificate authority** in AWS Certificate Manager **does all this for you automatically**, while you sleep.
