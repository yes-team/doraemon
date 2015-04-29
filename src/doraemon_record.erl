-module(doraemon_record).
-export([from_bin/1, clone/1, close/1]).
-export([get_value/2 , get_value/3, set_value/3, to_list/1, class/1, time/1, isset/2]).

clone(D)-> magic_record:clone(D).
close(D)-> magic_record:close(D).
get_value(K, D)-> magic_record:get_value(K, D, <<>>).
get_value(K, D, Default)-> magic_record:get_value(K, D, Default).
set_value(K, V, D)-> magic_record:set_value(K, V, D).
to_list(D) -> magic_record:to_list(D).
class(D) -> magic_record:get_value(<<"@class">>, D, <<>>).
time(D) -> magic_record:get_value(<<"@time">>, D, fun doraemon_timer:now/0).
isset(K,D) -> magic_record:isset(K,D).

from_bin(Bin)->
	D = magic_record:new(),
	D2 = parse_data_bin(Bin, D),
	case magic_record:get_value(<<"@time">>, D2, default) of
		undefined -> magic_record:set_value(<<"@time">>, doraemon_timer:now(), D);
		_ -> D2
	end.
parse_data_bin(<<K1:8, K:K1/binary, V1:2/big-unsigned-integer-unit:8, V:V1/binary, T/binary>>, D)->
	D2 = magic_record:set_value(K, V, D),
	parse_data_bin(T, D2);
parse_data_bin(<<0>>, D)-> D;
parse_data_bin(<<>>, D)-> D.
