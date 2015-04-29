-module(doraemon_db).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-record(state, {fd, meta}).
-include_lib("eunit/include/eunit.hrl").
-record(meta, {pos=0, eof=0, counter=0, maxsize=50*1024*1024, craete_time=0}).

-define(MAGIC_BIN, "aabbccabcccc").
-define(HEADER_SIZE, 100).
-define(MAGIC_BIN_LEN, 12).


%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/2, write/1, list/1, list/2]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(File, Size) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [File, Size], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([File, Size]) ->
    S = open(File, Size),
    {ok, S}.

handle_call({state}, _From, State) ->
    {reply, State, State};

handle_call({write, Bin}, _From, State) ->
    State2 = write_data(Bin, State),
    {reply, ok, State2};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

write(Data)->
    gen_server:call(?MODULE, {write, term_to_binary(Data)}).

state()->
    gen_server:call(?MODULE, {state}).

open(File, Size)->
    {ok, Fd} = file:open(File, [read, write, binary]),
    try
        {ok, <<MetaLen:16/big>>} = file:pread(Fd, 0, 2),
        {ok, MetaBin} = file:pread(Fd, 2, MetaLen),
        #state{fd=Fd, meta=binary_to_term(MetaBin)}
    catch _:_->
        #state{fd=Fd, meta=format(Fd, Size)}
    end.

format(Fd, Size)->
    file:truncate(Fd),
    Meta = #meta{craete_time=now(), maxsize=Size},
    write_meta(Fd, Meta),
    Meta.

write_meta(Fd, Meta)->
    Bin = term_to_binary(Meta),
    Size = erlang:byte_size(Bin),
    file:pwrite(Fd, 0, <<Size:16/big, Bin/binary>>).

write_data(<<>>, S)-> S;
write_data(Bin, S)->
    Size = erlang:byte_size(Bin),
    Meta2 = case (S#state.meta)#meta.pos + 3 + ?MAGIC_BIN_LEN + Size of
        Pos2 when Pos2 > (S#state.meta)#meta.maxsize ->
            file:pwrite(S#state.fd, (S#state.meta)#meta.pos + ?HEADER_SIZE, <<0>>),
            file:pwrite(S#state.fd, ?HEADER_SIZE, <<Bin/binary, ?MAGIC_BIN, Size:24/big>>),
            (S#state.meta)#meta{pos=Size + 3 + ?MAGIC_BIN_LEN, eof=(S#state.meta)#meta.pos};
        Pos2->
            file:pwrite(S#state.fd, (S#state.meta)#meta.pos + ?HEADER_SIZE, 
                <<Bin/binary, ?MAGIC_BIN, Size:24/big>>),
            (S#state.meta)#meta{pos = Pos2}
    end,
    write_meta(S#state.fd, Meta2),
    S#state{meta=Meta2}.

-record(find, {start=0, limit=20, match, state, loop=0, pos}).

list({Start, Limit})->
    list({Start, Limit}, fun(_)-> true end);
list(Limit)->
    list({0, Limit}).

list({Start, Limit}, Matcher) when is_integer(Start) and is_integer(Limit)->
    S = state(),
    lists:reverse(select(0, #find{start=Start, limit=Limit, match=Matcher, state=S,
                pos=(S#state.meta)#meta.pos, loop=0}, [])).

select(N, #find{start=Start, limit=Limit}, L) when N=:=Start+Limit -> L;
select(N, #find{loop=1, pos=P, state=S}, L) when P =< (S#state.meta)#meta.pos -> L;
select(N, #find{pos=0, state=S}=F, L) ->
    case (S#state.meta)#meta.eof of
        0 -> L;
        N when N>0 ->
            select(N, F#find{pos=(S#state.meta)#meta.eof, loop=1}, L)
    end;
select(N, #find{state=S, pos=Pos}=F, L)->
    case file:pread(S#state.fd, ?HEADER_SIZE + Pos - 3 - ?MAGIC_BIN_LEN, ?MAGIC_BIN_LEN + 3) of
    {ok, <<?MAGIC_BIN, Size:24/big>>} ->
        P2 =  Pos - Size - 3 - ?MAGIC_BIN_LEN,
        case file:pread(S#state.fd,?HEADER_SIZE + P2, Size) of
            {ok, Bin} ->
                Term = binary_to_term(Bin),
                F2 = F#find{pos=P2},
                case match(F#find.match,Term) of
                    true ->
                        if
                            N >= F#find.start ->
                                select(N+1, F2, [Term | L]);
                            true ->
                                select(N+1, F2, L)
                        end;
                    _ ->
                        select(N, F2, L)
                end;
            _->
                erlang:display(error_file)
        end;
    _ ->
        erlang:display(error_file),
        []
    end.

match(F, Term) when is_function(F)->
    F(Term);
match([], Term)-> true;
match([F|T], Term) when is_function(F)->
    case F(Term) of
        true ->
            match(T, Term);
        _ -> false
    end;
match(_,_)->false.
