-record(doraemon_topn, {id, name, time, interval_hours, total=0, data=[], limit=240}).
%-record(doraemon_bucket, {id , node , status=active}).
-record(doraemon_item, {id, type, name}).
-record(doraemon_alert, {interval=3600, left=[], right=[], mode=string, type=match_spec, test, sets=[], not_is=false}).
-record(topn_cmd, {name, item, hours=1, value=1, size=10, interval_hours=1, limit=240}).

%-define(BUCKET_NUM, 1).
-define(SYSTEM_COUNTER, "/system/incoming").

-define(T_AVG, 0).
-define(T_SUM, 1).
-define(T_MAX, 2).
-define(T_MIN, 3).

-record(update_args, {name, value=1, function=?T_SUM}).
-record(rrd_record, {time, value}).
-record(doraemon_nodes, {node, from}).
%-record(doraemon_session, {sess_id, user=[], data, update_time, ttl=1800}).
%-record(doraemon_cert, {key, secret,  status=active, join_time = doraemon_timer:now(),  acl=[], meta=[]}).

-record(msg_state, {queue_msg_tag, mq_req_channel, listener_name}).

%%-define(dio(X), spawn(io, format, ["[~p, ~p] : ~p\n", [?MODULE, ?LINE, X]])).
%%-define(diot(X), spawn(io, format, ["[~p, ~p] : ~p\n", [?MODULE, ?LINE, X]])).
-define(dio(X), skip).
-define(diot(X), skip).
