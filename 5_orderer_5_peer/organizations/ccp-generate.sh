#!/bin/bash

function one_line_pem {
    echo "`awk 'NF {sub(/\\n/, ""); printf "%s\\\\\\\n",$0;}' $1`"
}

function json_ccp {
    local PP=$(one_line_pem $6)
    local CP=$(one_line_pem $7)
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${ORGMSP}/$2/" \
        -e "s/\${MORG}/$3/" \
        -e "s/\${P0PORT}/$4/" \
        -e "s/\${CAPORT}/$5/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        ccp-template.json
}

function yaml_ccp {
    local PP=$(one_line_pem $6)
    local CP=$(one_line_pem $7)
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${ORGMSP}/$2/" \
        -e "s/\${MORG}/$3/" \
        -e "s/\${P0PORT}/$4/" \
        -e "s/\${CAPORT}/$5/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        ccp-template.yaml | sed -e $'s/\\\\n/\\\n          /g'
}

ORG=Org0
MORG=org0
ORGMSP=Org0
P0PORT=7051
CAPORT=7054
PEERPEM=crypto-config/peerOrganizations/org0.com/tlsca/tlsca.org0.com-cert.pem
CAPEM=crypto-config/peerOrganizations/org0.com/ca/ca.org0.com-cert.pem

echo "$(json_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org0.com/connection-org0.json
echo "$(yaml_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org0.com/connection-org0.yaml

ORG=Org1
MORG=org1
ORGMSP=Org1
P0PORT=8051
CAPORT=8054
PEERPEM=crypto-config/peerOrganizations/org1.com/tlsca/tlsca.org1.com-cert.pem
CAPEM=crypto-config/peerOrganizations/org1.com/ca/ca.org1.com-cert.pem

echo "$(json_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org1.com/connection-org1.json
echo "$(yaml_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org1.com/connection-org1.yaml

ORG=Org2
MORG=org2
ORGMSP=Org2
P0PORT=9051
CAPORT=9054
PEERPEM=crypto-config/peerOrganizations/org2.com/tlsca/tlsca.org2.com-cert.pem
CAPEM=crypto-config/peerOrganizations/org2.com/ca/ca.org2.com-cert.pem

echo "$(json_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org2.com/connection-org2.json
echo "$(yaml_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org2.com/connection-org2.yaml


ORG=Org3
MORG=org3
ORGMSP=Org3
P0PORT=10051
CAPORT=10054
PEERPEM=crypto-config/peerOrganizations/org3.com/tlsca/tlsca.org3.com-cert.pem
CAPEM=crypto-config/peerOrganizations/org3.com/ca/ca.org3.com-cert.pem

echo "$(json_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org3.com/connection-org3.json
echo "$(yaml_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org3.com/connection-org3.yaml

ORG=Org4
MORG=org4
ORGMSP=Org4
P0PORT=11051
CAPORT=11054
PEERPEM=crypto-config/peerOrganizations/org4.com/tlsca/tlsca.org4.com-cert.pem
CAPEM=crypto-config/peerOrganizations/org4.com/ca/ca.org4.com-cert.pem

echo "$(json_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org4.com/connection-org4.json
echo "$(yaml_ccp $ORG $ORGMSP $MORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > crypto-config/peerOrganizations/org4.com/connection-org4.yaml
