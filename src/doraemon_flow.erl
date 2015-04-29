-module(doraemon_flow).
-behaviour(gen_server).
-include("defined.hrl").
-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, join/1, link/0, leave/1,  close_all/2]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, 
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) ->
    io:format("starting ~p......\n", [?MODULE]),
    process_flag(trap_exit, true),
    ets:new(?MODULE, [protected, bag, named_table]),
    io:format("ok\n"),
    {ok, Args}.

handle_call(link, {Pid, _}, State) ->
    erlang:link(Pid),
    {reply,ok, State};

handle_call({join,Channel}, {Pid, _}, State) when is_binary(Channel) ->
    ets:insert(?MODULE, {{channel, Channel}, Pid}),
    ets:insert(?MODULE, {{pid, Pid}, {channel, Channel}}),
    {reply,ok, State};

handle_call({leave,Channel}, {Pid, _}, State) when is_binary(Channel) ->
    ets:delete_object(?MODULE, {{channel, Channel}, Pid}),
    ets:delete_object(?MODULE, {{pid, Pid}, {channel, Channel}}),
    {reply,ok, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({join,Channel, Pid}, State) when is_binary(Channel) ->
    ets:insert(?MODULE, {{channel, Channel}, Pid}),
    ets:insert(?MODULE, {{pid, Pid}, {channel, Channel}}),
    {noreply, State};
handle_cast({leave,Channel ,Pid},State) when is_binary(Channel) ->
    ets:delete_object(?MODULE, {{channel, Channel}, Pid}),
    ets:delete_object(?MODULE, {{pid, Pid}, {channel, Channel}}),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, _}, State) ->
    close_all(Pid, [filter, channel]),
    {noreply, State};

handle_info(_Info, State) ->
    io:format("info: ~p\n", [_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

link()->
    gen_server:call(?MODULE, link).


join(Channel)->
    gen_server:abcast(?MODULE, {join, Channel, self()}).

leave(Channel)->
    gen_server:abcast(?MODULE, {leave, Channel , self()}).

close_all(Pid, Opts)->
    case ets:lookup(?MODULE, {pid, Pid}) of
        [] -> ok;
        L -> 
            lists:foreach(fun({{pid,_}, Data}) ->
                    case Data of
                        {channel, Channel} ->
                            case lists:member(channel, Opts) of true ->
                                ets:delete_object(?MODULE, {{channel, Channel}, Pid}),
                                ets:delete_object(?MODULE, {{pid, Pid}, Data});
                            false -> ok end;
                        {filter, F}->
                            case lists:member(filter, Opts) of true ->
                                %ets:delete_object(filters, {F#bnow_filter.class, F}),
                                ets:delete_object(?MODULE, {{pid, Pid}, Data});
                            false -> ok end
                    end
                end, L)
    end.

