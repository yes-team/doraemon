-module(doraemon_bucket).
-behaviour(gen_server).
-include("defined.hrl").

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([ store/3, store/4, fetch/2, fetch/3, fold/3,fold/4 ]).
-compile(export_all).
-record(state, { db_fp , worker_num }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    DbRef = instance_db(),
	KernelCount = erlang:system_info(schedulers),
    {ok, #state{ db_fp = DbRef , worker_num = KernelCount }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({rrd,store,{T,K,V,F,S,C} , AmqpStatus}, #state{ db_fp = Db , worker_num = WorkerNum } = State) ->
    KLen = size(K)*8,
    <<KenGen:KLen/big>> = K,
    gen_server:cast( doraemon_rrd:whereis_name(KenGen rem WorkerNum +1) , {store,{ T,K,V,F,S,C } , AmqpStatus} ),
    {noreply, State}
;handle_cast({topn,store,{T,K,V,F,S}}, #state{ db_fp = Db } = State) ->
    %doraemon_rrd:store()
    todo
    ,{noreply, State}

%;handle_cast({move,},#state{db_fp = Db } = State) ->
%    {noreply , State}

;handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opuuuuuuuu.qquposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%-record(state, {fd}).

%-define(CHILD(I, M), { list_to_atom(M++integer_to_list(I)), {list_to_atom(M), start_link, []}, permanent, 5000, worker, [I]}).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

    
path() ->
    {ok, Datadir} = application:get_env(doraemon, datadir),
    filename:join(Datadir, "kv.db/" ).

instance_db() ->
    Path = path()
    ,filelib:ensure_dir(Path)
    ,{ok, Ref} = eleveldb:open(Path, [{create_if_missing, true} , {compression , true} ,{sst_block_size , 32*1024*1024}, {write_buffer_size, 1024*1024*1024} , {cache_size , 16*1024*1024*1024} ,{use_bloomfilter , true} ])
    ,ets:insert( doraemon_global , {bucket_db_fp , Ref} )
    ,Ref.

db() ->
    [{_ , Db}|_] = ets:lookup(doraemon_global , bucket_db_fp)
    ,Db.

%update( rrd, T, K, V,F,S,C)->
%    gen_server:cast(  ?MODULE , { rrd,store,{T,K,V,F,S,C}}  )
%;update( topn, T, K, V,F,S,C)->
%    gen_server:cast(  ?MODULE , { topn,store,{T,K,V,F,S,C}}  ).
%
%update( Node , rrd, T, K, V,F,S,C)->
%    gen_server:cast(  {?MODULE,Node} , { rrd,store,{T,K,V,F,S,C}}  )
%;update( Node , topn, T, K, V ,F,S,C)->
%    gen_server:cast(  {?MODULE,Node} , { topn,store,{T,K,V,F,S,C}}  ).

store( K, V, Opt)->
    store(db() , K, V, Opt).
store( Db, K, V, Opt)->
    eleveldb:put( Db, K, V, Opt).

fetch( K, Opt)->
    fetch( db(), K, Opt).
fetch( Db, K, Opt)->
    case eleveldb:get( Db , K, [{fill_cache , true} |[{verify_checksums ,false }|Opt] ]) of
        {ok,  V} -> 
            {ok, V};
        Other -> Other
    end.
fold( Fun, InitialAcc, Opt)-> 
    fold(db() , Fun , InitialAcc , Opt).
fold( Db, Fun, InitialAcc, Opt)-> 
     eleveldb:fold( Db, 
        fun({K, V}, L)->
             Fun({K, V}, L)
        end, InitialAcc, Opt).


    


%move_bucket( Start , End , Time ,  ToNode ) -> 
%    %begin_move( Id ),
%    Path = path(),
%    {ok, Ref} = eleveldb:open(Path, [{compression , true} ,{sst_block_size , 32*1024*1024},{use_bloomfilter , true} ])
%    %,SourceDbRef = db( Id )
%   % ,{ok , Fp} = file:open( path( Id ), [read] )
%    ,ok = rpc:call( ToNode , ?MODULE , begin_move, [Id] )
%    ,ok = gen_server:call( { name( Id ) , node() } , close_db )
%    ,{ok , Files} = file:list_dir( path( Id ) )
%    ,ok = lists:foreach( fun(File) -> 
%        { ok, Fp } = file:open( Path ++ "/" ++ File , [read])
%        ,ok = rpc:call( ToNode , ?MODULE , do_move , [ Id , File, Fp ] ) 
%        ,file:close(Fp)
%    end ,Files )
%    ,ok = rpc:call( ToNode , ?MODULE , end_move, [ Id ] )
%    ,lists:foreach( fun(F) -> file:delete( Path ++ "/" ++ F) end , Files )
%    ,file:del_dir( Path )
%    ,ok.
%
%begin_move( Id ) -> 
%    {ok , _Pid} = bnow_bucket:start_link( Id , tmp )
%    ,TmpDb = db( {id , Id } )
%    ,bnow_global:store( { bucket_tmp_db_fp , Id } , TmpDb )
%    ,[ThisBucket] = mnesia:dirty_read( bnow_bucket , Id )
%    ,mnesia:dirty_write(ThisBucket#bnow_bucket{ status = write_only , node = node() } )
%    ,ok.
%
%do_move( Id, Filename , SrcFp ) ->
%    %,Pid
%    F = path( Id ) ++"/"++ Filename
%    %,io:format( "file ~p \n\n" , [F] )
%    ,filelib:ensure_dir( F )
%    ,{ok , Fp} = file:open( F, [write] )
%    ,ok = move_file(SrcFp , Fp)
%    ,file:close(Fp)
%    ,ok.
%
%end_move( Id ) ->
%    bnow_bucket_sup:unload( Id )
%    ,bnow_bucket_sup:load(Id)
%    ,[ThisBucket] = mnesia:dirty_read( bnow_bucket , Id )
%    ,mnesia:dirty_write(ThisBucket#bnow_bucket{ status = active , node = node() } )
%    ,ThisDb = db({id , Id})
%    ,TmpDb = bnow_global:fetch( {bucket_tmp_db_fp , Id } )
%    ,eleveldb:fold( TmpDb , fun( {K,V},_Y ) -> eleveldb:put( ThisDb ,K,V,[] ) end , [] , [] )
%    %,TmpBucketPid ! {stop, self()}
%    ,name( Id , tmp ) ! {stop, self()}
%    ,receive _ -> ok end
%    ,TmpPath = path(Id , tmp)
%    ,{ok, TmpFiles} = file:list_dir( TmpPath )
%    ,[ file:delete( TmpPath ++ "/" ++ X ) || X <- TmpFiles ]
%    ,file:del_dir( TmpPath )
%    ,file:del_dir( filename:dirname( TmpPath ) )
%    ,ok.
%    %,spawn( ?MODULE , wait_file , [ {Pid ,Fp } ] ).
%
%move_file(Sfp , Fp) ->
%    case file:read( Sfp , 10 * 1024 * 1024 ) of
%        eof ->  ok
%        ;{ok , Part} -> file:write( Fp , Part ), move_file(Sfp,Fp)
%    end.
%    
%store(Bucket, K, V, Opt)->eleveldb:put(db(Bucket), K, <<Bucket:16/big, V/binary>>, Opt).
%fetch(Bucket, K, Opt)->
%    case eleveldb:get(db(Bucket), K, [{fill_cache , true} |[{verify_checksums ,false }|Opt] ]) of
%        {ok, <<_:16, V/binary>>} -> {ok, V};
%        Other -> Other
%    end.
%fold(Bucket, Fun, InitialAcc, Opt)-> 
%
% eleveldb:fold(db(Bucket), 
%     fun({K, <<_:16, V/binary>>}, L)->
%             Fun({K, V}, L)
%     end, InitialAcc, Opt).
%
