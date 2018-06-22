#!/usr/bin/env escript
%% -*- erlang -*-
%%! -smp enable -sname test_client

-mode(compile).

main(Args) ->
    try
        NumClients = get_client_count(Args),
        io:format("[INFO] running '~p' bad clients~n", [NumClients]),
        Bin = read_header_file(),
        PPid = self(),
        WPid = start_waiter(PPid, NumClients),
        run_bad_clients(NumClients, WPid, Bin, 1),
        wait_for_waiter(PPid)
    catch
        Err:Reason ->
            io:format(standard_error, "[ERROR]: ~p Reason: ~p~n", [Err, Reason]),
            usage()
    end.

usage() ->
    io:format("usage: test-client [client_count]~n"),
    halt(1).

wait_for_waiter(PPid) ->
    receive
        {PPid, alldone} ->
            io:format("[INFO] exiting~n");
        Msg ->
            io:format("[INFO] main receive got unexpected message: ~p~n", [Msg]),
            wait_for_waiter(PPid)
    end.

get_client_count([String]) ->
    list_to_integer(String);
get_client_count(_) ->
    unlimited.

read_header_file() ->
    {ok, Bin} = file:read_file("amqp-header.bin"),
    Bin.

start_waiter(PPid, NumClients) ->
    WaiterFun = fun() ->
                    wait_clients(PPid, NumClients)
                end,
    WPid = spawn(WaiterFun),
    io:format("[INFO] spawned waiter: ~p~n", [WPid]),
    WPid.

wait_clients_loop(PPid, unlimited) ->
    wait_clients(PPid, unlimited);
wait_clients_loop(PPid, Count) when is_integer(Count) ->
    wait_clients(PPid, Count - 1).

wait_clients(PPid, 0) ->
    io:format("[INFO] all clients done.~n"),
    PPid ! {PPid, alldone};
wait_clients(PPid, Count) ->
    SPid = self(),
    receive
        {SPid, done, CPid, ClientId} ->
            io:format("[INFO] client ~p with ID ~p done.~n", [CPid, ClientId]),
            wait_clients_loop(PPid, Count);
        Msg ->
            io:format("[INFO] received unexpected message: ~p~n", [Msg])
    after 15075 ->
        % Timeout should be just a bit larger than the max time a bad
        % client can be running
        io:format("[INFO] huh, still waiting on a client to finish...~n"),
        wait_clients_loop(PPid, Count)
    end.

run_bad_clients_loop(unlimited, WPid, Bin, Idx) ->
    run_bad_clients(unlimited, WPid, Bin, Idx + 1);
run_bad_clients_loop(Count, WPid, Bin, Idx) when is_integer(Count) ->
    run_bad_clients(Count - 1, WPid, Bin, Idx + 1).

run_bad_clients(0, _WPid, _Bin, _Idx) ->
    io:format("[INFO] all bad clients are now running.~n");
run_bad_clients(Count, WPid, Bin, Idx) ->
    StartFun = fun() ->
                   bad_client(WPid, Idx, Bin)
               end,
    CPid = spawn(StartFun),
    io:format("[INFO] spawned: ~p~n", [CPid]),
    Millis = rand:uniform(6500) + 1000,
    ok = timer:sleep(Millis),
    run_bad_clients_loop(Count, WPid, Bin, Idx).

bad_client(WPid, ClientId, Bin) ->
    {ok, S} = gen_tcp:connect("localhost", 5672, []),
    Millis0 = rand:uniform(7500) + 25,
    ok = timer:sleep(Millis0),
    ok = gen_tcp:send(S, Bin),
    Millis1 = rand:uniform(7500) + 25,
    ok = timer:sleep(Millis1),
    ok = gen_tcp:close(S),
    WPid ! {WPid, done, self(), ClientId}.
