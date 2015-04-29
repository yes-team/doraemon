-module(doraemon_var).
-export([bin/1, atom/1, bool/1, list/1, int/1, int/2, float/1,
        float/2, number/1, number/2, guid/1, guid/2, guid/3]).
-export([get_app_env/2,get_app_env/3, right_at/1]).

bin(B) when is_binary(B)->B;
bin(B) when is_atom(B)->list_to_binary(atom_to_list(B));
bin(B) when is_integer(B)-> list_to_binary(integer_to_list(B));
bin(B)-> list_to_binary(list(B)).

atom(A) when is_atom(A)-> A;
atom(A) when is_list(A)-> list_to_atom(A);
atom(A)-> atom(list(A)).

list(A) when is_list(A)-> A;
list(A) when is_atom(A)-> atom_to_list(A);
list(A) when is_binary(A)-> binary_to_list(A);
list(A) when is_integer(A)-> integer_to_list(A);
list(A) -> io_lib:format("~p", [A]).


int(V) -> int(V, 0).
int(V, _) when is_integer(V) -> V;
int(V, _) when is_float(V) -> erlang:round(V);
int([], Default) -> Default;
int(V, Default) ->
    S = list(V),
    case string:to_integer(S) of
        {error, _} -> Default;
        {N,_ } -> N
    end.

float(V) -> float(V, 0.0).
float(V, _) when is_float(V) -> V;
float(V, _) when is_integer(V) -> V * 1.0;
float([], Default) -> Default;
float(V, Default) ->
    S = list(V),
    case string:to_float(S) of
        {error, _} -> Default;
        {N,_ } -> N
    end.

number(V)-> number(V, 0).
number(V, Default)->
    case float(V, not_float) of
        not_float -> int(V, Default);
        N when is_float(N) -> N
    end.

bool(V)->
    case atom(V) of
        true -> true;
        yes -> true;
        on -> true;
        _ -> false
    end.

guid(Len) -> guid(Len, fun(_)-> true end).
guid(Len, Fun)-> guid(Len, Fun, 10).
guid(Len, Fun, 0) -> {error, reach_max_guid_try_limit};
guid(Len, Fun, Step) when (Len>0) and (Len=<32) ->
    <<N:128>> = erlang:md5(erlang:term_to_binary({erlang:now(),self(),node(),Step})),
    Value = list_to_binary(string:substr(lists:flatten(io_lib:format("~-32.36.0B",[N])), 1, Len)),
    case Fun(Value) of
        false -> guid(Len,Fun, Step-1);
        _ -> {ok, Value}
    end.

get_app_env(App, Arg) ->
    get_app_env(App,Arg,undefined).
get_app_env(App, Arg, Default) ->
    case application:get_env(App, Arg) of
        undefined ->
            Default;
        {ok, Value} ->
            Value
    end.

right_at([])->error;
right_at([$@|R])-> R;
right_at([_|T])->right_at(T).
