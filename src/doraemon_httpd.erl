-module(doraemon_httpd).
-behaviour(cowboy_http_handler).
-export([start_link/0]).
-export([init/3, handle/2, terminate/2]).
-include_lib("kernel/include/file.hrl").
-include_lib("cowboy/include/http.hrl").
-include("defined.hrl").
-compile(export_all).
-record(state, { basedir}).

init({_Any, http}, Req, []) ->
	{ok, Req, #state{}}.

handle(R, S) ->
    {ok, R2} = cowboy_http_req:reply(404, [{<<"Content-Type">>, <<"text/html">>}], "<h1>404 Not found</h1><hr />", R),
    {ok, R2, S}.

terminate(_Req, _State) -> ok.

start_link()->
    Dispatch = [ {'_', [ 
%            { [<<"api">>, <<"live">>] , doraemon_webflow, []},
            { [<<"api">>, <<"live">>] , doraemon_webflow, []},
            { [<<"api">>, '...'] , doraemon_webapi, []},
            { '_', ?MODULE, []}
        ]} ],

    {ok, {Ip, Port}} = application:get_env(doraemon,web_listen),
	cowboy:start_listener(httpd, 100,
		cowboy_tcp_transport, [{port, Port}, {ip, Ip}],
		cowboy_http_protocol, [{dispatch, Dispatch}]).
		
content_type(<<".js">>)-> <<"text/javascript;charset=utf-8">>;
content_type(<<".css">>)-> <<"text/css">>;
content_type(<<".html">>)-> <<"text/html;charset=utf-8">>;
content_type(<<".htm">>)-> <<"text/html;charset=utf-8">>;
content_type(<<".txt">>)-> <<"text/plain;charset=utf-8">>;
content_type(<<".png">>)-> <<"image/png">>;
content_type(<<".gif">>)-> <<"image/gif">>;
content_type(<<".jpg">>)-> <<"image/jpeg">>;
content_type(<<".jpeg">>)-> <<"image/jpeg">>;
content_type(_)-> <<"application/octet-stream">>.

root_path(Filepath)->
    L = filename:split(Filepath),
    L2 = lists:reverse(L),
    root_path_check(L, []).
root_path_check([], L)-> filename:join(lists:reverse(L));
root_path_check([".." | T], [A | L])-> root_path_check(T, L);
root_path_check([<<"..">> | T], [A | L])-> root_path_check(T, L);
root_path_check([H | T], L)->
    root_path_check(T, [H | L]).

read_file_info(Filepath)->
    case ets:lookup(doraemon_cache, {file_info, Filepath}) of
        [] ->
            Ret = file:read_file_info(Filepath),
            ets:insert(doraemon_cache, {{file_info, Filepath}, Ret}),
            Ret;
        [{_, Ret} | _] -> Ret
    end.

read_file(Filepath)->
    case ets:lookup(doraemon_cache, {file, Filepath}) of
        [] ->
            Ret = file:read_file(Filepath),
            ets:insert(doraemon_cache, {{file, Filepath}, Ret}),
            Ret;
        [{_, Ret} | _] -> Ret
    end.

run(Base_dir, Path, R, S, APP)->
    case  doraemon_global:fetch(running) of
        true ->
            %do_run(Base_dir, Path, R, S, APP);
            {ok, R2} = cowboy_http_req:reply(404, [{<<"Content-Type">>, <<"text/html">>}], 
                "<h1>404 Not found</h1><hr />", R),
            {ok, R2, S};
        _ ->
            {ok, R2} = cowboy_http_req:reply(200, [{<<"Content-Type">>, <<"text/html">>}], 
                "<h1>Application starting...</h1><hr />", R),
            {ok, R2, S}
    end.

do_run(Base_dir, Path, R, S, APP)->
    Filepath = filename:join([Base_dir | Path]),
    %io:format("~p= ~p\n", [Path, Filepath]),
    case read_file_info(Filepath) of
        {ok, #file_info{type=regular, access=Access}=F} when ( Access =:= read ) or ( Access =:= read_write ) ->
%            case filename:extension(Filepath) of
%                <<".php">> ->
%                    run_php(R, [
%                    {<<"DORAEMON_APIGATE">>, S#state.gateport},
%                    {<<"DORAEMON_APP">>, APP},
%                    {<<"DORAEMON_APPDIR">>, S#state.appdir},
%                    {<<"DORAEMON_BASEDIR">>, S#state.basedir},
%                    {<<"SCRIPT_FILENAME">>, root_path(Filepath)},
%                    {<<"SCRIPT_NAME">>, R#http_req.raw_path}], S);
%                Ext->
                    Ext = filename:extension(Filepath),
                    ContentType = content_type(Ext),
                    {ok, Content} = read_file(Filepath),
                    {ok, R2} = cowboy_http_req:reply(200, 
                        [{<<"Content-Type">>, ContentType}], Content, R),
                    {ok, R2, S};
%            end;
        {ok, #file_info{type=directory, access=Access}=F} when ( Access =:= read ) or ( Access =:= read_write ) ->
            % io:format("~p ~p\n",[R#http_req.raw_path, binary:last(R#http_req.raw_path)]), 
            case binary:last(R#http_req.raw_path) of
                $/ ->
                    run(Base_dir, Path ++ [<<"index.php">>], R#http_req{path= R#http_req.path ++ ["index.php"], 
                        raw_path= << (R#http_req.raw_path)/binary,"index.php">> }, S, APP);
                _ ->
                    {ok, R2} = cowboy_http_req:reply(302, [{<<"Location">>, << (R#http_req.raw_path)/binary,"/">> }], "", R),
                    {ok, R2, S}
            end;
        _ ->
            {ok, R2} = cowboy_http_req:reply(404, [{<<"Content-Type">>, <<"text/html">>}], 
                "<h1>404 Not found</h1><hr />", R),
            {ok, R2, S}
    end.

%gc()->
%    gc_session(mnesia:dirty_first(doraemon_session), doraemon_timer:now()).
%
%gc_session('$end_of_table', _)->ok;
%gc_session(K, Now)->
%    case mnesia:dirty_read(doraemon_session, K) of
%        [S|_] ->
%            Next = mnesia:dirty_next(doraemon_session, K),
%            if 
%                Now - S#doraemon_session.update_time > S#doraemon_session.ttl ->
%                    mnesia:dirty_delete(doraemon_session, K);
%                true -> ok
%            end,
%            gc_session(Next, Now);
%        _ -> ok
%    end.

priv_dir(App)->
    case code:priv_dir(App) of
        {error,bad_name} ->
            AppStr = atom_to_list(App),
            Path = code:where_is_file(AppStr++".app"),
            N = string:len(Path) - string:len(AppStr) - 5,
            string:substr(Path, 1, N) ++ "/../priv";
        Path when is_list(Path) -> Path
    end.

%------------------------------------------------------

-record(cgi_head, {status = 200 , type, location, headers = []}).
-define(CGI_Timeout, 15000).

%run_php( Req = #http_req{method = Method,
%               version = Version,
%               raw_qs = RawQs,
%               raw_host = RawHost,
%               port = Port,
%               headers = Headers}, CGIParams, State) ->
%    
%    {{Address, _Port}, Req1} = cowboy_http_req:peer(Req),
%    AddressStr = inet_parse:ntoa(Address),
%    CGIParams2 = [{<<"GATEWAY_INTERFACE">>, <<"CGI/1.1">>},
%                  {<<"QUERY_STRING">>, RawQs},
%                  {<<"REMOTE_ADDR">>, AddressStr},
%                  {<<"REMOTE_HOST">>, AddressStr},
%                  {<<"REQUEST_METHOD">>, method(Method)},
%                  {<<"SERVER_NAME">>, RawHost},
%                  {<<"SERVER_PORT">>, integer_to_list(Port)},
%                  {<<"SERVER_PROTOCOL">>, protocol(Version)},
%                  {<<"SERVER_SOFTWARE">>, <<"Cowboy">>} |
%                  CGIParams],
%    CGIParams3 = params(Headers, CGIParams2),
%
%    {ok, State}.
%    %Server = whereis(doraemon_fcgi),
%    %case ex_fcgi:begin_request(Server, responder, CGIParams3, ?CGI_Timeout) of
%    %  error ->
%    %    {ok, Req2} = cowboy_http_req:reply(502, [], [], Req1),
%    %    {ok, Req2, State};
%    %  {ok, Ref} ->
%    %    Req3 = case cowboy_http_req:body(Req1) of
%    %      {ok, Body, Req2} ->
%    %        ex_fcgi:send(Server, Ref, Body),
%    %        Req2;
%    %      {error, badarg} ->
%    %        Req1 end,
%    %    Fun = fun decode_cgi_head/3,
%    %    {ok, Req4} = case fold_k_stdout(#cgi_head{}, <<>>, Fun, Ref) of
%    %      {Head, Rest, Fold} ->
%    %        case acc_body([], Rest, Fold) of
%    %          error ->
%    %            cowboy_http_req:reply(502, [], [], Req3);
%    %          timeout ->
%    %            cowboy_http_req:reply(504, [], [], Req3);
%    %          CGIBody ->
%    %            send_response(Req3, Head, CGIBody) end;
%    %      error ->
%    %        cowboy_http_req:reply(502, [], [], Req3);
%    %      timeout ->
%    %        cowboy_http_req:reply(504, [], [], Req3) end,
%    %    {ok, Req4, State} end.
        
method('GET') ->
  <<"GET">>;
method('POST') ->
  <<"POST">>;
method('PUT') ->
  <<"PUT">>;
method('HEAD') ->
  <<"HEAD">>;
method('DELETE') ->
  <<"DELETE">>;
method('OPTIONS') ->
  <<"OPTIONS">>;
method('TRACE') ->
  <<"TRACE">>;
method(Method) when is_binary(Method) ->
  Method.

protocol({1, 0}) ->
  <<"HTTP/1.0">>;
protocol({1, 1}) ->
  <<"HTTP/1.1">>.

params(Params, Acc) ->
  F = fun ({Name, Value}, Acc1) ->
        case param(Name) of
          ignore ->
            Acc1;
          ParamName ->
            case Acc1 of
              [{ParamName, AccValue} | Acc2] ->
                % Value is counter-intuitively prepended to AccValue
                % because Cowboy accumulates headers in reverse order.
                [{ParamName, [Value, value_sep(Name) | AccValue]} | Acc2];
              _ ->
                [{ParamName, Value} | Acc1] end end end,
  lists:foldl(F, Acc, lists:keysort(1, Params)).

value_sep('Cookie') ->
  % Accumulate cookies using a semicolon because at least one known FastCGI
  % implementation (php-fpm) doesn't understand comma-separated cookies.
  $;;
value_sep(_Header) ->
  $,.

param('Accept') ->
  <<"HTTP_ACCEPT">>;
param('Accept-Charset') ->
  <<"HTTP_ACCEPT_CHARSET">>;
param('Accept-Encoding') ->
  <<"HTTP_ACCEPT_ENCODING">>;
param('Accept-Language') ->
  <<"HTTP_ACCEPT_LANGUAGE">>;
param('Cache-Control') ->
  <<"HTTP_CACHE_CONTROL">>;
param('Content-Base') ->
  <<"HTTP_CONTENT_BASE">>;
param('Content-Encoding') ->
  <<"HTTP_CONTENT_ENCODING">>;
param('Content-Language') ->
  <<"HTTP_CONTENT_LANGUAGE">>;
param('Content-Length') ->
  <<"CONTENT_LENGTH">>;
param('Content-Md5') ->
  <<"HTTP_CONTENT_MD5">>;
param('Content-Range') ->
  <<"HTTP_CONTENT_RANGE">>;
param('Content-Type') ->
  <<"CONTENT_TYPE">>;
param('Cookie') ->
  <<"HTTP_COOKIE">>;
param('Etag') ->
  <<"HTTP_ETAG">>;
param('From') ->
  <<"HTTP_FROM">>;
param('If-Modified-Since') ->
  <<"HTTP_IF_MODIFIED_SINCE">>;
param('If-Match') ->
  <<"HTTP_IF_MATCH">>;
param('If-None-Match') ->
  <<"HTTP_IF_NONE_MATCH">>;
param('If-Range') ->
  <<"HTTP_IF_RANGE">>;
param('If-Unmodified-Since') ->
  <<"HTTP_IF_UNMODIFIED_SINCE">>;
param('Location') ->
  <<"HTTP_LOCATION">>;
param('Pragma') ->
  <<"HTTP_PRAGMA">>;
param('Range') ->
  <<"HTTP_RANGE">>;
param('Referer') ->
  <<"HTTP_REFERER">>;
param('User-Agent') ->
  <<"HTTP_USER_AGENT">>;
param('Warning') ->
  <<"HTTP_WARNING">>;
param('X-Forwarded-For') ->
  <<"HTTP_X_FORWARDED_FOR">>;
param(Name) when is_atom(Name) ->
  ignore;
param(Name) when is_binary(Name) ->
  <<"HTTP_", (<< <<(param_char(C))>> || <<C>> <= Name >>)/binary>>.

param_char($a) -> $A;
param_char($b) -> $B;
param_char($c) -> $C;
param_char($d) -> $D;
param_char($e) -> $E;
param_char($f) -> $F;
param_char($g) -> $G;
param_char($h) -> $H;
param_char($i) -> $I;
param_char($j) -> $J;
param_char($k) -> $K;
param_char($l) -> $L;
param_char($m) -> $M;
param_char($n) -> $N;
param_char($o) -> $O;
param_char($p) -> $P;
param_char($q) -> $Q;
param_char($r) -> $R;
param_char($s) -> $S;
param_char($t) -> $T;
param_char($u) -> $U;
param_char($v) -> $V;
param_char($w) -> $W;
param_char($x) -> $X;
param_char($y) -> $Y;
param_char($z) -> $Z;
param_char($-) -> $_;
param_char(Ch) -> Ch.

fold_k_stdout(Acc, Buffer, Fun, Ref) ->
  receive Msg -> fold_k_stdout(Acc, Buffer, Fun, Ref, Msg) end.

fold_k_stdout(Acc, Buffer, Fun, Ref, {ex_fcgi, Ref, Messages}) ->
  fold_k_stdout2(Acc, Buffer, Fun, Ref, Messages);
fold_k_stdout(_Acc, _Buffer, _Fun, Ref, {ex_fcgi_timeout, Ref}) ->
  timeout;
fold_k_stdout(Acc, Buffer, Fun, Ref, _Msg) ->
  fold_k_stdout(Acc, Buffer, Fun, Ref).

fold_k_stdout2(Acc, Buffer, Fun, _Ref, [{stdout, eof} | _Messages]) ->
  fold_k_stdout2(Acc, Buffer, Fun);
fold_k_stdout2(Acc, Buffer, Fun, Ref, [{stdout, NewData} | Messages]) ->
  Cont = fun (NewAcc, Rest, NewFun) ->
    fold_k_stdout2(NewAcc, Rest, NewFun, Ref, Messages) end,
  Fun(Acc, <<Buffer/binary, NewData/binary>>, Cont);
fold_k_stdout2(Acc, Buffer, Fun, _Ref,
              [{end_request, _CGIStatus, _AppStatus} | _Messages]) ->
  fold_k_stdout2(Acc, Buffer, Fun);
fold_k_stdout2(Acc, Buffer, Fun, Ref, [_Msg | Messages]) ->
  fold_k_stdout2(Acc, Buffer, Fun, Ref, Messages);
fold_k_stdout2(Acc, Buffer, Fun, Ref, []) ->
  fold_k_stdout(Acc, Buffer, Fun, Ref).

fold_k_stdout2(Acc, <<>>, Fun) ->
  Cont = fun (_NewAcc, _NewBuffer, _NewFun) -> error end,
  Fun(Acc, eof, Cont);
fold_k_stdout2(_Acc, _Buffer, _Fun) ->
  error.

decode_cgi_head(_Head, eof, _More) ->
  error;
decode_cgi_head(Head, Data, More) ->
  case erlang:decode_packet(httph_bin, Data, []) of
    {ok, Packet, Rest} ->
      decode_cgi_head(Head, Rest, More, Packet);
    {more, _} ->
      More(Head, Data, fun decode_cgi_head/3);
    _ ->
      error end.

-define(decode_default(Head, Rest, More, Field, Default, Value),
  case Head#cgi_head.Field of
    Default ->
      decode_cgi_head(Head#cgi_head{Field = Value}, Rest, More);
    _ ->
      % Decoded twice the same CGI header.
      error end).

decode_cgi_head(Head, Rest, More, {http_header, _, <<"Status">>, _, Value}) ->
  ?decode_default(Head, Rest, More, status, 200, Value);
decode_cgi_head(Head, Rest, More,
                {http_header, _, 'Content-Type', _, Value}) ->
  ?decode_default(Head, Rest, More, type, undefined, Value);
decode_cgi_head(Head, Rest, More, {http_header, _, 'Location', _, Value}) ->
  ?decode_default(Head, Rest, More, location, undefined, Value);
decode_cgi_head(Head, Rest, More,
                {http_header, _, << "X-CGI-", _NameRest >>, _, _Value}) ->
  % Dismiss any CGI extension header.
  decode_cgi_head(Head, Rest, More);
decode_cgi_head(Head = #cgi_head{headers = Headers}, Rest, More,
                {http_header, _, Name, _, Value}) ->
  NewHead = Head#cgi_head{headers = [{Name, Value} | Headers]},
  decode_cgi_head(NewHead, Rest, More);
decode_cgi_head(Head, Rest, More, http_eoh) ->
  {Head, Rest, More};
decode_cgi_head(_Head, _Rest, _Name, _Packet) ->
  error.

acc_body(Acc, eof, _More) ->
  lists:reverse(Acc);
acc_body(Acc, Buffer, More) ->
  More([Buffer | Acc], <<>>, fun acc_body/3).

-spec send_response(#http_req{}, #cgi_head{}, [binary()]) -> {ok, #http_req{}}.
send_response(Req, #cgi_head{location = <<$/, _/binary>>}, _Body) ->
  % @todo Implement 6.2.2. Local Redirect Response.
  cowboy_http_req:reply(502, [], [], Req);
send_response(Req, Head = #cgi_head{location = undefined}, Body) ->
  % 6.2.1. Document Response.
  send_document(Req, Head, Body);
send_response(Req, Head, Body) ->
  % 6.2.3. Client Redirect Response.
  % 6.2.4. Client Redirect Response with Document.
  send_redirect(Req, Head, Body).

-spec send_document(#http_req{}, #cgi_head{}, [binary()]) -> {ok, #http_req{}}.
send_document(Req, #cgi_head{type = undefined}, _Body) ->
  cowboy_http_req:reply(502, [], [], Req);
send_document(Req, #cgi_head{status = Status, type = Type, headers = Headers},
              Body) ->
  reply(Req, Body, Status, Type, Headers).

-spec send_redirect(#http_req{}, #cgi_head{}, [binary()]) -> {ok, #http_req{}}.
send_redirect(Req, #cgi_head{status = Status = <<$3, _/binary>>,
                             type = Type,
                             location = Location,
                             headers = Headers}, Body) ->
  reply(Req, Body, Status, Type, [{'Location', Location} | Headers]);
send_redirect(Req, #cgi_head{type = Type,
                             location = Location,
                             headers = Headers}, Body) ->
  reply(Req, Body, 302, Type, [{'Location', Location} | Headers]).

%% @todo Filter headers like Content-Length.
reply(Req, Body, Status, undefined, Headers) ->
  cowboy_http_req:reply(Status, Headers, Body, Req);
reply(Req, Body, Status, Type, Headers) ->
  cowboy_http_req:reply(Status, [{'Content-Type', Type} | Headers], Body, Req).

