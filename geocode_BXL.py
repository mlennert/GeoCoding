# -*- coding: utf-8 -*-

#Script to access the geocoding service of UrbIS (Brussels, Belgium,
# http://cirb.brussels/fr/nos-solutions/urbis-solutions/urbis-tools)
#This code uses the suds library https://fedorahosted.org/suds/

#Name of the file containing the adresses to be geocoded
#File without header and with seperator '|'
fadresses='XXXX.csv'

#Position of the different data elements in the address file
cid=0
crue=1
cnum=2
ccp=3
cville=4

#Import of libraries
import time
import urllib2
import os
import copy
import logging
import codecs
from suds.client import Client

#Function for attributing different parts of addressType
def parse_adresse(composantes_adresse):
    addressType.street.name=composantes_adresse[crue]
    addressType.street.postCode=composantes_adresse[ccp]
    addressType.street.municipality=composantes_adresse[cville]
    addressType.number=composantes_adresse[cnum]
    return addressType

#Function getting matched addresses from connexion and identifying address with highest geocodeMatchCode
#First paramater (language) stays empty to allow both French and Dutch addresses

def geocode_and_get_best(addressType):
    
    resultat_adresse = connexion.service.getAddressesFields('', addressType)
    max=-1
    compteur = 0
    bon = 999
    if resultat_adresse:
        for adresse in resultat_adresse:
            if adresse.geocodeMatchCode > max:
                max = adresse.geocodeMatchCode
                bon = compteur
            compteur = compteur + 1
        return (resultat_adresse[bon], compteur)
    else:
        return(None, -1)

def geocode(addressType):

    resultat_adresse, compteur = geocode_and_get_best(addressType)

    if resultat_adresse:
        if (not resultat_adresse.address.number) and addressType.number:
            #interpolate with closest numbers above and below
            interpolated_x, interpolated_y, num_status = interpolate(addressType)
            resultat_adresse.address.number=num_status
            if num_status != 'not found':
                resultat_adresse.point.x = interpolated_x
                resultat_adresse.point.y = interpolated_y
            else:
                num_status='no number'
                resultat_adresse.address.number=num_status
    else:
        resultat_adresse=None

    return(resultat_adresse, compteur)


def interpolate(addressType):
    #Interpolate coordonates from the closest house numbers (either even or
    #interpoler coordonnées à partir des numéros de maison autour (par pas de 2)
    #We limit the search to the closest 10 numbers on each side
    address_above=copy.deepcopy(addressType)
    address_below=copy.deepcopy(addressType)
    address_above.number=int(address_above.number)+2
    address_below.number=int(address_below.number)-2    
    result_above, compteur = geocode_and_get_best(address_above)
    result_below, compteur = geocode_and_get_best(address_below)
    limit=0
    while not result_above.address.number and limit < 10:
        address_above.number+=2
        result_above, compteur = geocode_and_get_best(address_above)
        limit+=1
    if limit == 10:
        result_above.address.number=None

    limit=0
    while not result_below.address.number and address_below.number>0 and limit < 10:
        address_below.number-=2
        result_below, compteur = geocode_and_get_best(address_below)
        limit+=1
    if limit == 10:
        result_below.address.number=None

    number_above = -1
    number_below = -1
    original_number=int(addressType.number)
    if result_above.address.number:
        number_above=int(result_above.address.number)
        x_above = float(result_above.point.x)
        y_above = float(result_above.point.y)
    if result_below.address.number:
        number_below=int(result_below.address.number) 
        x_below = float(result_below.point.x)
        y_below = float(result_below.point.y)
        
    if number_above > -1 and number_below > -1:
        numstatus='between ' + str(number_below) + ' and ' + str(number_above)
        distance=1.0*(original_number-number_below)/(number_above-number_below)

        if x_above > x_below:
            interpol_x = x_below + (x_above-x_below)*distance
        else:
            interpol_x = x_below - (x_below-x_above)*distance
        if y_above > y_below:
            interpol_y = y_below + (y_above-y_below)*distance
        else:
            interpol_y = y_below - (y_below-y_above)*distance

    if number_above > -1 and number_below == -1:
        numstatus='closest=' + str(number_above)
        interpol_x = x_above
        interpol_y = y_above
    if number_above == -1 and number_below > -1:
        numstatus='closest=' + str(number_below)
        interpol_x = x_below
        interpol_y = y_below
    if number_above == -1 and number_below == -1:
        numstatus='not found'
        interpol_x = interpol_y = 0
 
    return(interpol_x, interpol_y, numstatus)

#URL of the geocoding service
url = 'http://service.gis.irisnet.be/urbis/Localization?wsdl'

#Log settings for suds
logging.basicConfig(level=logging.WARNING)
logging.getLogger('suds.client').setLevel(logging.WARNING)

#Open connection to URL
connexion = Client(url)

#In order to see data types and functions available on the server use the
#following command
#print connexion

#Open file for results
f = open('geocoded_addresses.csv', 'w')

#Creation of a variable of type Address as defined on the server
addressType = connexion.factory.create('ns1:AddressType')
addressType.street=connexion.factory.create('ns1:StreetType')

nadresses = 0

with codecs.open(fadresses, mode='r', encoding='utf-8') as fichier_adresses:
    for adresse in fichier_adresses:


        nadresses+=1
        if nadresses == 1 or nadresses % 1000 == 0:
            currenttime = time.strftime("%d/%m %X", time.localtime())
            print currenttime + ": adresse %d" % nadresses


#Parse the line of data and fill the Address data structure
#then send it to geocoding
        composantes_adresse=adresse.split('|')
        addressType=parse_adresse(composantes_adresse)
        resultat_adresse, compteur = geocode(addressType)

        if resultat_adresse:
#Create output by concatenation of different address elements and coordinates
            resultat = composantes_adresse[cid] + '|' + resultat_adresse.address.street.name + '|' + str(resultat_adresse.address.number) + '|' + str(resultat_adresse.address.street.postCode) + '|' + str(resultat_adresse.address.street.municipality) + '|' + str(resultat_adresse.point.x) + '|' + str(resultat_adresse.point.y) + '|' + str(resultat_adresse.geocodeMatchCode) + '|' + str(compteur) + '\n' 
        else:
            resultat = composantes_adresse[cid] + '||||||||\n'
#Write result to file
        f.write(resultat.encode('utf-8'))

#Close files
fichier_adresses.close()
f.close()
