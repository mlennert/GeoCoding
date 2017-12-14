#Script for geocoding using the Spanish CartoCiudad geocoder with REST protocol

from __future__ import print_function
import requests
import json
import codecs
import time
import urllib2
import os

#Open file for writing results
f = open('geocoded_addresses.csv', 'w')

#URL of geocoding server
url = 'http://www.cartociudad.es/CartoGeocoder/Geocode?address='

#Name of file containing the addresses to be geocoded
fadresses='es_adresses_test.csv'

nadresses = 0

with codecs.open(fadresses, mode='r', encoding='utf-8') as fichier_adresses:
        for adresse in fichier_adresses:

            #Print progress info
            nadresses+=1
            if nadresses == 1 or nadresses % 1000 == 0:
                currenttime = time.strftime("%d/%m %X", time.localtime())
                print(currenttime + ": adresse %d" % nadresses)
                                            
            #Parse current address line and construct query string
            composantes_adresse=adresse.split('|')
            id = composantes_adresse[0]
            query_adresse = ','.join([composantes_adresse[1], composantes_adresse[2], composantes_adresse[3]])

            query= url+query_adresse

            #Call server with query string, watching out for too long query
            #timeouts
            try:
                response = requests.get(query, timeout=30)

                #Test response (in JSON format) to check whether we got a valid
                #result
                try:
                    response_length=len(json.loads(response.text)['result'])
                    if response_length>0:

                        status = json.loads(response.text)['result'][0]['status']
                        if not status:
                            status=''
                        nb_results = len(json.loads(response.text)['result'])
                        if not nb_results:
                            nb_results=''
                        x = json.loads(response.text)['result'][0]['longitude']
                        if not x:
                            x = -9999
                        y = json.loads(response.text)['result'][0]['latitude']
                        if not y:
                            y = -9999
                        road_type = json.loads(response.text)['result'][0]['road_type']
                        road_name = json.loads(response.text)['result'][0]['road_name']
                        if road_type:
                            road_found = road_type + ' ' + road_name
                        else:
                            if road_name:
                                road_found = road_name
                            else: road_found =''
                        municipality_found = json.loads(response.text)['result'][0]['municipality']
                        if not municipality_found:
                            municipality_found=''
        
                        #Construct output
                        resultat = id + '|' + str(status) + '|' + str(nb_results) + '|' + road_found + '|' + municipality_found + '|' + str(x) + '|' + str(y) + '\n'
                    else:
                        resultat = id + '||||||\n'
                except KeyboardInterrupt:
                    sys.exit()
                except:
                        resultat = id + '|999|||||\n'
            except KeyboardInterrupt:
                sys.exit()
            except :
                currenttime = time.strftime("%d/%m %X", time.localtime())
                print(currenttime + ": Timeout")
                resultat = id + '|998|||||\n'
    
            #Write result to output file
            f.write(resultat.encode('utf-8'))

#Close files
fichier_adresses.close()
f.close()
