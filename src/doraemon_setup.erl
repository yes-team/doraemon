%%%-------------------------------------------------------------------
%%% @copyright 2013 ShopEx Network Technology Co, .Ltd
%%% @author liyouyou <liyouyou@shopex.cn>
%%% @doc
%%% doraemon_setup.erl
%%% @end
%%% Created : 2013/07/17 03:01:03 liyouyou
%%% #Time-stamp: <syrett 2013-07-22 10:05:13>
%%%-------------------------------------------------------------------

-module(doraemon_setup).

-compile(export_all).

-export([add_node/1, forget_node/1]).
-export([join/1]).
-export([init/0]).
-export([clear_db/0, all_tables/0]).
-export([install_table/1, install_table/2, reinstall_table/1]).
-compile(export_all).

-include("defined.hrl").

%%%===================================================================
%%% Common interface: init_system/join_system/upgrade
%%%===================================================================
init_system() ->
    init().

join_system(Node) ->
    join(Node).

%%%===================================================================
%%% Internal functions
%%%===================================================================
add_node(Node)->
    pong = net_adm:ping(Node),
    mnesia:change_config(extra_db_nodes, [Node]),
    mnesia:change_table_copy_type(schema, Node, disc_copies),
    rpc:call(Node, mnesia, wait_for_tables, [schema]),
    forget_node(Node),
    [mnesia:add_table_copy(T, Node, disc_copies) || T <- all_tables()],
    ok.

forget_node(Node)->
    [mnesia:del_table_copy(T, Node) || T <- all_tables()].

clear_db()->
    try
        mnesia:stop(),
        mnesia:delete_schema([node()]),
        mnesia:start()
    catch _:_->
            %% TODO: log error/warning here
            ok
    end.

join(N)->
    clear_db(),
    case rpc:call(N, ?MODULE, add_node, [node()]) of
        ok -> io:format("cluster joined\n");
        {error, Why} -> io:format("failed: ~s\n", [Why]);
        Other -> io:format("Unknow status: ~p\n", [Other])
    end,
    application:stop(doraemon),
    application:start(doraemon),
    ok.

init()->
    application:stop(doraemon),
    clear_db(),
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    A = [install_table(T) || T <- all_tables()],
    ?dio(A),
    mnesia:stop(),
    mnesia:start(),
	L = [T || {T, _} <- all_tables()],
    ok = mnesia:wait_for_tables(L, 1000),
    doraemon_divide:add_node( <<>> , node() ),
    %mnesia:stop(),
    application:start(doraemon), 
    ok.

install_table({Table, DiscType}) ->
    install_table([node()], {Table, DiscType});
install_table(Table)->
    install_table([node()],{Table, disc_copies}).

install_table(Nodes, {Table,DiscType})->
    L = read_record_info(Table),
    mnesia:create_table(Table,[
        {type,set},
        {DiscType, Nodes},
        {attributes, L}
    ]);

install_table(_,_)->nothing.

read_record_info(Table) ->
    case Table of
        doraemon_nodes -> record_info(fields, doraemon_nodes)
        %doraemon_session -> record_info(fields, doraemon_session);
        %doraemon_cert -> record_info(fields, doraemon_cert)
    end.


reinstall_table(Table)->
    mnesia:delete_table(Table),
    install_table(Table).

all_tables()-> 
    [{doraemon_nodes, disc_copies}
%    {doraemon_topn , disc_copies},
%    {doraemon_item , disc_copies},
%    {topn_cmd , disc_copies}
%     {doraemon_session, disc_copies},
     %{doraemon_cert, disc_copies}
     ].


