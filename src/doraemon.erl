-module(doraemon).
-export([start/0, stop/0]).
-include("defined.hrl").
-include("vsn.hrl").
-compile(export_all).

start()->
    application:start(?MODULE).

stop()->
    application:stop(?MODULE).

version()-> ?doraemon_vsn.
licence()-> {free_user}.


