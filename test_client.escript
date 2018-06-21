#!/usr/bin/env escript
%% -*- erlang -*-
%%! -smp enable -sname test_client

-mode(compile).

main([String]) ->
    try
        Count = list_to_integer(String),
        io:format("[INFO] running ~p bad clients~n", [Count]),
        {ok, Bin} = file:read_file("amqp-header.bin"),
        PPid = self(),
        WaiterFun = fun() ->
                        wait_clients(PPid, Count)
                    end,
        WPid = spawn(WaiterFun),
        io:format("[INFO] spawned waiter: ~p~n", [WPid]),
        run_bad_clients(Count, WPid, Bin),
        receive
            {PPid, alldone} ->
                io:format("[INFO] exiting~n")
        after 120000 ->
            io:format(standard_error, "[ERROR] waited too long for clients, exiting!~n", []),
            halt(1)
        end
    catch
        Err:Reason ->
            io:format(standard_error, "[ERROR]: ~p Reason: ~p~n", [Err, Reason]),
            usage()
    end;
main(_) ->
    usage().

usage() ->
    io:format("usage: test-client clients~n"),
    halt(1).

wait_clients(PPid, 0) ->
    io:format("[INFO] all clients done.~n"),
    PPid ! {PPid, alldone};
wait_clients(PPid, Count) ->
    SPid = self(),
    receive
        {SPid, done, CPid, ClientId} ->
            io:format("[INFO] client ~p with ID ~p done.~n", [CPid, ClientId]),
            wait_clients(PPid, Count - 1);
        Msg ->
            io:format("[INFO] received unexpected message: ~p~n", [Msg])
    after 5000 ->
        io:format("[INFO] huh, still waiting on bad clients...~n"),
        wait_clients(PPid, Count)
    end.

run_bad_clients(0, WPid, _Bin) ->
    io:format("[INFO] all bad clients are now running.~n");
run_bad_clients(Count, WPid, Bin) ->
    StartFun = fun() ->
                   bad_client(WPid, Count, Bin)
               end,
    CPid = spawn(StartFun),
    io:format("[INFO] spawned: ~p~n", [CPid]),
    Millis = rand:uniform(500) + 25,
    ok = timer:sleep(Millis),
    run_bad_clients(Count - 1, WPid, Bin).

bad_client(WPid, ClientId, Bin) ->
    {ok, S} = gen_tcp:connect("localhost", 5672, []),
    Millis0 = rand:uniform(5000) + 25,
    ok = timer:sleep(Millis0),
    ok = gen_tcp:send(S, Bin),
    Millis1 = rand:uniform(5000) + 25,
    ok = timer:sleep(Millis1),
    ok = gen_tcp:close(S),
    WPid ! {WPid, done, self(), ClientId}.
