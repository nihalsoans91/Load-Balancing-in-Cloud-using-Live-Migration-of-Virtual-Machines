#!/bin/sh
echo "hello $USER your login date is" $(/bin/date)
if [ -z "$1" ]
then 
    echo please enter server no
    read sername
    hostser="server$sername"
    serno=$sername
else
serno=$1
hostser="server$1"
fi
clear
# Initialization

rm -f /waste/*
count=0
cpu=0
i=0
ac=0
ar=0
noofser=2
vmt="WindowsXP"
vmu=0
echo $hostser
seruuid=$(xe host-list name-label=$hostser |grep -a uuid|cut -c 29-100)
echo $seruuid
nvm=$(xe vm-list resident-on=$seruuid power-state=running|grep name|wc -l|cut -c 1-2)
nvm=`expr $nvm - 1`
echo $nvm
fg=$(xe vm-list resident-on=$seruuid power-state=running|grep vm|head -n $nvm|cut -c 24-100)
echo "$fg" >> /waste/vname.txt


while read rescheeed
do
 xl sched-credit -d $rescheeed -c 10
 echo $rescheeed
  xl sched-credit
done < /waste/vname.txt

# this function is used to scale the resouces that is used by the VM 1-scaling percentage 2-scaling rule 3- VM name 4-Ram or CPU
function scale 
{ 
  case $4 in
  1)
   if [ $2 -eq 1 ]
   then
       echo "scaling up CPU of $3 by $1 % "
       sca=$(xl sched-credit|grep -a $3|cut -c 48-50)

       if [ $sca -lt 100 ]
       then
   	   cap1=`expr $sca \* $1`
           cap2=$(expr $cap1 / 100)
           recap=`expr $sca + $cap2`
           if [ $recap -lt  100 ]
           then
           xl sched-credit -d $3 -c $recap
           echo "Scaling Complete"
       else 
           xl sched-credit -d $3 -c 100
           echo "You have reached the maximum hardware performance of your physical machine"
           echo "further scaling not possible"
           fi
       fi
   fi
   if [ $2 -eq 0 ]
   then
       echo "scaling down CPU of $3 by $1 % "
       sca=$(xl sched-credit|grep -a $3|cut -c 48-50)

      if [ $sca -gt 20 ]
       then
	   ucap1=`expr $sca \* $1`
           ucap2=`expr $ucap1 / 100`
           recap=`expr $sca - $ucap2`
           xl sched-credit -d $3 -c $recap
           echo "Scaling Complete"
           return 1
       fi
   fi
   ;;
  2)   
       vmu=$(xe vm-list name-label=$vmt power-state=running|grep uuid|cut -c 24-59)
       sat_min=$(xe vm-param-get uuid=$vmu param-name=memory-static-min)
       sat_max=$(xe vm-param-get uuid=$vmu param-name=memory-static-max)
       dyn_min=$(xe vm-param-get uuid=$vmu param-name=memory-dynamic-min)
       dyn_max=$(xe vm-param-get uuid=$vmu param-name=memory-dynamic-max)
   if [ $2 -eq 0 ]
   then
       echo "scaling down RAM of $3 by $1 % "
       if [ $dyn_max -lt $sat_min ]
	then
          pc=`expr $1 / 100`
	  rt=`expr $dyn_max \* $pc`
          dyn_smax=`expr $dyn_max + $rt`
          xe vm-param-set uuid=$vmu memory-dynamic-max=$dyn_smax
        fi   
       
   fi
   if [ $2 -eq 1 ]
   then
       echo "scaling up RAM of $3 by $1 % "
       if [ $dyn_max -lt $sat_min ]
	then
          pc=`expr $1 / 100`
	  rt=`expr $dyn_max \* $pc`
          dyn_smax=`expr $dyn_max + $rt`
          xe vm-param-set uuid=$vmu memory-dynamic-max=$dyn_smax
	fi
   fi
     ;;
  esac
}


# this function migrates the VM up the server
function migrateup
{
  echo " migrate to higher";
  d=`expr $serno + 1`
  if [ $d -ge $noofser ] && [ $d -gt 0 ]
  then
  vmu=$(xe vm-list name-label=$vmt power-state=running|grep uuid|cut -c 24-59)
  xe vm-migrate vm=$vmu destination=$hostser host=server$d
  
  fi
  }


# this function is used to migrate down the server
function migratedown
{
  z=`expr $serno - 1`
   echo  "migrate to lower";
  echo $z "--" $hostser
  if [ $z -gt 0 ]
  then
  vmuz=$(xe vm-list name-label=$vmt power-state=running|grep uuid|cut -c 24-60)
  echo $vmt " --" $vmuz 
  xe vm-migrate vm=$vmuz destination="$hostser" host="server$z"
  fi  
}

# function to mark the server
function mfml
{
  echo "$1 marked for migration later ";
}

# function to calculate the CPU utilization
function calcpu
{
cpu="$(xentop -v -b -i 2|grep $vmt|cut -c 32-35)"
#echo "current cpu utilization $cpu"
echo "$cpu" >> /waste/egc$i.txt              # for debugging
act=$(cut -c 1-2 /waste/egc$i.txt|head -n 2|tail -n 1)
#echo $act					# for debugging
sc=$(xl sched-credit|grep -a $vmt|cut -c 48-50)
pac=`expr $act \* 100`
ac=`expr $pac / $sc`
}


function calram
{
ram="$(xentop -v -b -i 1|grep $vmt|cut -c 50-54)"
echo "$ram" >> /waste/egr$i.txt
ar=$(cut -c 1-2 /waste/egr$i.txt|head -n 1)
}

# main function

while [ $count -lt 2 ]
do
nvm=$(xe vm-list resident-on=$seruuid power-state=running|grep name|wc -l|cut -c 1-2)
nvm=`expr $nvm - 1`
if [ $nvm -gt 0 ]
then
while read vmt
do
temp1=$(xl sched-credit|grep -a $vmt|cut -c 48-50)
if [ $temp1 -eq 0 ]
then
    xl sched-credit -d $vmt -c 10
    echo "correctify";
fi
echo "----------------------------------Detected $vmt------------------------------"
calcpu
echo "comparing cpu usage $ac"

if [ "$ac" -gt 70 ] && [ "$ac" -lt 95 ];
	then
		scale 10 1 $vmt 1
		sleep 3
		calcpu
            	if [ "$ac" -gt 70 ] && [ "$ac" -lt 95 ];
	            then
                         scale 10 1 $vmt 1
			         sleep 3
			         calcpu
                fi
            	if [ "$ac" -gt 70 ] && [ "$ac" -lt 95 ];
	            then
                         migrateup
                	fi
fi
calcpu
if [ "$ac" -gt 95 ];
then
  scale 20 1 $vmt 1
  sleep 3
  calcpu
  if [ "$ac" -gt 95 ];
    then
    migrateup 
    fi
fi
calcpu
if [ "$ac" -le 10 ]
then
     scale 20 0 $vmt 1
     sleep 3
     calcpu
     if [ "$ac" -le 10 ]
     then
	  scale 20 0 $vmt 1
	  sleep 3
          calcpu
          if [ "$ac" -le 10 ]
          then
            migratedown
	     fi
	fi
fi
calram
echo "comparing ram usage $ar"
if [ "$ar" -gt 70 ] && [ "$ar" -lt 95 ];
	then
		scale 20 1 $vmt 2
		sleep 3
		calram
            	if [ "$ar" -gt 70 ] && [ "$ar" -lt 95 ];
	            then
                         scale 20 1 $vmt 2
			         sleep 3
			 calram
                fi
            	if [ "$ar" -gt 70 ] && [ "$ar" -lt 95 ];
	            then
                         migrateup
                	fi
                	 
      		       
fi
calram
if [ "$ar" -gt 95 ];
then
  scale 40 1 $vmt 2
  calram
  if [ "$ar" -gt 95 ];
    then
    migrateup 
    fi
fi
calram
if [ "$ar" -lt 10 ]
then
     scale 20 0 $vmt 2
     sleep 3
     calram
     if [ "$ar" -lt 10 ]
     then
	  scale 20 0 $vmt 2
	  sleep 3
          calram
          if [ "$ar" -lt 10 ]
          then
            migratedown
	     fi
	fi
fi	
i=`expr $i + 1`
echo "$ac" >> /log/xencp.log

done < /waste/vname.txt
fi
rm -f /waste/vname.txt
nvm=$(xe vm-list resident-on=$seruuid power-state=running|grep name|wc -l|cut -c 1-2)
nvm=`expr $nvm - 1`
clear
if [ $nvm -lt 1 ]
then 
     echo "There is no vm running on this server"
     echo "The server is in Stand by mode"
else 
echo "no of vm in the system " $nvm
fi
fg=$(xe vm-list resident-on=$seruuid power-state=running|grep vm|head -n $nvm|cut -c 24-100)
echo "$fg" >> /waste/vname.txt
done
