-module(doraemon_app).
-include("defined.hrl").
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, ensure_started/1]).

%-record(state, {filter_table}).

start(_StartType, _StartArgs) ->
    ensure_started(mnesia),
    %ensure_started(ex_fcgi),
    ensure_started(cowboy),
    doraemon_sup:start_link().

stop(_State) ->
    ok.

ensure_started(App)->
    case proplists:get_value(App, application:which_applications()) of
        undefined->
            application:start(App);
        _ -> ok
    end.
