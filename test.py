import urllib.request
import json

req = urllib.request.Request('http://localhost:8030/api/v1/auth/login', data=b'{"phone_number":"0755960594"}', headers={'Content-Type': 'application/json'})
urllib.request.urlopen(req)

req2 = urllib.request.Request('http://localhost:8030/api/v1/auth/verify', data=b'{"phone_number":"0755960594","otp":"123456"}', headers={'Content-Type': 'application/json'})
resp2 = urllib.request.urlopen(req2)
token = json.loads(resp2.read().decode())['access_token']

req3 = urllib.request.Request('http://localhost:8030/api/v1/bookings', headers={'Authorization': 'Bearer ' + token})
resp3 = urllib.request.urlopen(req3)
res = json.loads(resp3.read().decode())
print("COUNT:", len(res))
if res:
    print("FIRST ITEM KEYS:", list(res[0].keys()))
