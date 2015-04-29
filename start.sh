#!/bin/sh

n=`echo $1 | sed 's/[^0-9]*//g'`
if [ "X$n" = "X" ]; then
    datadir="data"
    node_name="doraemon"
    n=0
else
    datadir="data.$n"
    node_name="doraemon$n"
fi

zmq_listen="tcp://0.0.0.0:`expr 5858 + $n`"
web_listen=`expr 8889 + $n`
gate_port=`expr 16000 + $n`
test -d $datadir/log || mkdir -p $datadir/log

echo "******************************************************"
owd=`pwd`
cd $datadir
echo "* CMD: $0 $*"
echo "* data dir:  `pwd`"
echo "* zmq port:  $zmq_listen"
echo "* web port:  $web_listen"
echo "* gate port: $gate_port"
echo "* node name: $node_name"
echo "******************************************************"
echo "     \\   ^__^"
echo "      \\  (oo)\\_______"
echo "         (__)\\  [$n]  )\\/\\"
echo "              ||----w |"
echo "              ||     ||"
cd $owd

exec erl -pa ebin deps/*/ebin -boot start_sasl \
        -smp enable \
                -sname $node_name \
                -config rel/files/app.config \
        -doreamon datadir "\"$datadir\"" \
        -doreamon web_listen "{{0,0,0,0}, $web_listen}" \
        -doraemon gate_port $gate_port \
        -doreamon zmq_listen "\"$zmq_listen\"" \
	-sasl sasl_error_logger "{file, \"$datadir/sasl.log\"}" \
        -mnesia dir "\"$datadir/mnesia\"" \
        -os_mon start_cpu_sup true \
        -os_mon start_disksup false \
        -os_mon start_memsup true \
        -s doraemon \
	-heart \
        +K true \
        +P 65535 \
        +hms 46368 \
        +hmbs 317811 \
        -kernel error_logger silent

        #-sasl error_logger_mf_dir "\"$datadir/log\"" \
        #-sasl error_logger_mf_maxbytes 8192 \
        #-sasl error_logger_mf_maxfiles 4 \
