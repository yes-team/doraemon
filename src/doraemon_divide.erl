%%%-------------------------------------------------------------------
%%% @copyright 2013 ShopEx Network Technology Co, .Ltd
%%% @author liyouyou <liyouyou@shopex.cn>
%%% @doc
%%% doraemon_divide.erl
%%% @end
%%% Created : 2013/07/16 03:59:05 liyouyou
%%% #Time-stamp: <syrett 2013-09-06 14:27:33>
%%%-------------------------------------------------------------------

-module(doraemon_divide).

-include("defined.hrl").

-compile(export_all).


add_node(From, Node) ->
    {atomic, ok} = mnesia:transaction(fun() ->
                                              mnesia:write(#doraemon_nodes{node = Node, from = From})
                                      end),
    ok.

init() ->    
    build().

build() ->
    {atomic, TupleList}  = mnesia:transaction(fun () ->
                                                 mnesia:foldl(fun(E, Acc0) ->
                                                                      [{E#doraemon_nodes.from, E#doraemon_nodes.node} | Acc0]

                                                              end, [], doraemon_nodes)
                                         end),
    TL_sort = lists:sort(TupleList),

    Head = ["-module(doraemon_divide_runtime).\n",
            "-export([get_node/1]).\n\n"],
    
    Func = lists:foldl(fun({Rule, Node}, Acc0) ->
                               Term = [io_lib:format("get_node(Key) when ~p =< Key ->\n", [Rule]),
                                       io_lib:format("~p;\n", [Node])],
                               [Term | Acc0]
                       end, [], TL_sort),
    
    Tail = ["get_node(_) -> \n",
            atom_to_list( node() ) , ".\n\n"
           ],

    ErlSrc = lists:flatten(Head ++ Func ++ Tail),
    DR = file:write_file("data/doraemon_divide_runtime.erl", list_to_binary(ErlSrc)),
    try
        IncDir = include_dir(),
        {module, doraemon_divide_runtime} = dynamic_compile:load_from_string(
                ErlSrc, [{i, IncDir}, inline])
    catch _:Err->
        erlang:display({error, Err}),
        io:format("~s\n", [ErlSrc])
    end.

include_dir()->
    case code:lib_dir(bnow, include) of
        {error, _}-> "include";
        Path -> Path
    end.

test() ->
    Key1 = <<"ABdfdf">>,
    Key2 = <<"Baa">>,
    Key3 = <<"Bbefft">>,
    Key4 = <<"CdfecgeSDg">>,
    Key5 = <<"aF">>,
    List = [{<<"A">>, node1}, {<<"Aa">>, node2}, {<<"Bac">>, node3}, {<<"aD">>, node4}],
    [add_node(F, N) || {F, N} <- List],
    node1 = doraemon_divide_runtime:get_node(Key1),
    node2 = doraemon_divide_runtime:get_node(Key2),
    node3 = doraemon_divide_runtime:get_node(Key3),
    node3 = doraemon_divide_runtime:get_node(Key4),
    node4 = doraemon_divide_runtime:get_node(Key5),
    mnesia:dirty_delete({doraemon_nodes, Key1}),
    mnesia:dirty_delete({doraemon_nodes, Key2}),
    mnesia:dirty_delete({doraemon_nodes, Key3}),
    mnesia:dirty_delete({doraemon_nodes, Key4}),
    mnesia:dirty_delete({doraemon_nodes, Key5}),
    ok.
