#!/bin/bash

# ++ +++ +++++++ # ++++++++ +++++++ # ++++++ +++++++++ # ++++++++++ # ++++++ +++++++ ++ #
# ++ --- ------- # -------- ------- # ------ --------- # ---------- # ------ ------- ++ #
# ++                                                                                 ++ #
# ++  Set up both an on-premises (root) and an AWS Certificate Manager (subordinate) ++ #
# ++  certificate authority. The former signs the CSR of the latter and the new plus ++ #
# ++  chain certificates are imported thus activating the AWS subordinate CA.        ++ #
# ++                                                                                 ++ #
# ++ --- ------- # -------- ------- # ------ --------- # ---------- # ------ ------- ++ #
# ++ +++ +++++++ # ++++++++ +++++++ # ++++++ +++++++++ # ++++++++++ # ++++++ +++++++ ++ #


echo "" ; echo "" ;
echo "### ################################################# ###"
echo "### Config JSON for Creating an AWS CM Subordinate CA ###"
echo "### ################################################# ###"
echo ""

while read line
do
    fileline=`eval echo "$line"`
    echo "$fileline" >> "subordinate-ca-config.json"
done < "subordinate-ca-template.json"
jq '.' subordinate-ca-config.json


echo ""
echo "### ####################################################### ###"
echo "### Create AWS Cert Manager Subordinate CA and Download CSR ###"
echo "### ####################################################### ###"
echo ""

SUBORDINATE_CA_ARN=`aws acm-pca create-certificate-authority \
    --certificate-authority-configuration file://$PWD/subordinate-ca-config.json \
    --certificate-authority-type "SUBORDINATE" \
    --idempotency-token $(date +"%y%j%H%M") | jq -r '.CertificateAuthorityArn'`

echo ""
echo "AWS Certificate Manager Subordinate CA created."
echo "Subordinate CA Name => $SUBORDINATE_CA_CN"
echo "Subordinate CA ARN  => $SUBORDINATE_CA_ARN"
echo ""


echo ""
echo "### ######################################################### ###"
echo "### Download the Certificate Signing Request when it is ready ###"
echo "### ######################################################### ###"
echo ""

aws acm-pca wait certificate-authority-csr-created \
    --certificate-authority-arn $SUBORDINATE_CA_ARN

aws acm-pca describe-certificate-authority \
    --certificate-authority-arn $SUBORDINATE_CA_ARN

aws acm-pca get-certificate-authority-csr \
    --certificate-authority-arn $SUBORDINATE_CA_ARN \
    --output text \
    > /root/cert.directory/$SUBORDINATE_CA_CN-subordinate-ca-csr.pem


echo ""
echo "### #####################################################b################# ###"
echo "### Create On-Premises Root CA, Sign CSR of Subordinate CA and Import Certs ###"
echo "### #####################################################b################# ###"
echo ""

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

chmod 444 /root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-cert.pem
echo "openssl x509 -noout -text -in $ON_PREMISES_CA_CN-on-premises-ca-cert.pem"

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
    -out     /root/cert.directory/$SUBORDINATE_CA_CN-subordinate-ca-cert.pem \
    2>/dev/null ;

echo "openssl x509 -noout -text -in $SUBORDINATE_CA_CN-subordinate-ca-cert.pem"

openssl verify \
    -CAfile /root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-cert.pem \
    /root/cert.directory/$SUBORDINATE_CA_CN-subordinate-ca-cert.pem

aws acm-pca import-certificate-authority-certificate \
    --certificate-authority-arn $SUBORDINATE_CA_ARN  \
    --certificate       file:///root/cert.directory/$SUBORDINATE_CA_CN-subordinate-ca-cert.pem \
    --certificate-chain file:///root/cert.directory/$ON_PREMISES_CA_CN-on-premises-ca-cert.pem


echo ""
echo "### ############################################# ###"
echo "### SSL PEM Certificates and Key Collateral Files ###"
echo "### ############################################# ###"
echo ""

ls -lah; echo ""; ls -lah /root/cert.directory ; echo "" ;

exit 0
