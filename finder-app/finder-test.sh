#!/bin/sh
# Tester script for assignment 1 and assignment 2
# Author: Siddhant Jajoo

set -e
set -u

NUMFILES=10
WRITESTR=AELD_IS_FUN
WRITEDIR=/tmp/aeld-data

# 1. Usar la ruta absoluta de configuración para Buildroot
username=$(cat /etc/finder-app/conf/username.txt)

if [ $# -lt 3 ]
then
	echo "Using default value ${WRITESTR} for string to write"
	if [ $# -lt 1 ]
	then
		echo "Using default value ${NUMFILES} for number of files to write"
	else
		NUMFILES=$1
	fi	
else
	NUMFILES=$1
	WRITESTR=$2
	WRITEDIR=/tmp/aeld-data/$3
fi

# 2. ELIMINADO: Ya no hacemos "make" aquí, Buildroot ya compiló el writer.

MATCHSTR="The number of files are ${NUMFILES} and the number of matching lines are ${NUMFILES}"

echo "Writing ${NUMFILES} files containing string ${WRITESTR} to ${WRITEDIR}"

rm -rf "${WRITEDIR}"

# 3. Leer de la configuración del sistema
assignment=$(cat /etc/finder-app/conf/assignment.txt)

if [ $assignment != 'assignment1' ]
then
	mkdir -p "$WRITEDIR"

	if [ -d "$WRITEDIR" ]
	then
		echo "$WRITEDIR created"
	else
		exit 1
	fi
fi

for i in $( seq 1 $NUMFILES)
do
	# 4. Usar "writer" sin "./" porque está en el PATH (/usr/bin)
	writer "$WRITEDIR/${username}$i.txt" "$WRITESTR"
done

# 5. Usar "finder.sh" sin "./"
OUTPUTSTRING=$(finder.sh "$WRITEDIR" "$WRITESTR")

# remove temporary directories
rm -rf /tmp/aeld-data

set +e

# 6. Escribir el resultado en el archivo que pide el assignment
echo "${OUTPUTSTRING}" > /tmp/assignment4-result.txt

# Verificar el éxito (para la consola)
echo ${OUTPUTSTRING} | grep "${MATCHSTR}"
if [ $? -eq 0 ]; then
	echo "success"
	exit 0
else
	echo "failed: expected ${MATCHSTR} in ${OUTPUTSTRING} but instead found"
	exit 1
fi
