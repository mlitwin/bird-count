API Docs https://documenter.getpostman.com/view/664302/S1ENwy59

curl --location 'https://api.ebird.org/v2/data/obs/KZ/recent' \
--header 'X-eBirdApiToken: {{x-ebirdapitoken}}'

curl --location 'https://api.ebird.org/v2/ref/region/info/CA' \
--header 'X-eBirdApiToken: {{x-ebirdapitoken}}'

export EBIRDAPITOKEN=

curl --location 'https://api.ebird.org/v2/ref/region/info/CA' --header "X-eBirdApiToken: ${EBIRDAPITOKEN}"

curl --location 'https://api.ebird.org/v2/ref/region/list/subnational2/US' --header "X-eBirdApiToken: ${EBIRDAPITOKEN}"

curl --location 'https://api.ebird.org/v2/data/obs/US/recent' --header "X-eBirdApiToken: ${EBIRDAPITOKEN}" > US.json

curl --location 'https://api.ebird.org/v2/data/obs/US-ME/recent' --header "X-eBirdApiToken: ${EBIRDAPITOKEN}" > US-ME.json


curl --location 'https://api.ebird.org/v2/data/obs/US-CA/recent' --header "X-eBirdApiToken: ${EBIRDAPITOKEN}" > US-CA.json


curl --location 'https://api.ebird.org/v2/data/obs/US-CA-041/recent' --header "X-eBirdApiToken: ${EBIRDAPITOKEN}" > US-CA-041.json

