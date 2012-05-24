-module(poker).
-export([deck/0, shuffle/1, shuffle/2, rank_compare/2, hands/0, hand/1, hand_compare/2]).
-export([suits/0, ranks/0]).
-export([hidden_game/0]).
-export([multiplayer_game/2, multi_game/2, stat_multi_game/3]).
-export([test_hand/0, test_hand_compare/0, test_hand_compare_exact/0, test_speed/2, test_speed_hidden_game/1, test_random_multiplayer/1]).

suits() ->
    [ spades,
      clubs,
      hearts,
      diamonds
    ].

ranks() ->
    [ ace,
      king,
      queen,
      jack,
      ten,
      nine,
      eight,
      seven,
      six,
      five,
      four,
      three,
      two
    ].

hands() ->
    [
      royal_flush,
      straight_flush,
      four_of_kind,
      full_house,
      flush,
      straight,
      three_of_kind,
      two_pair,
      one_pair,
      high_card
    ].

deck() ->
    [{S,R} || S <- suits(), R <- ranks()].

shuffle(Deck) ->
    PD = [{random:uniform(), C} || C <- Deck],
    [C || {_, C} <- lists:keysort(1, PD)].

shuffle(Deck, 1) -> shuffle(Deck);
shuffle(Deck, Times) when Times > 1 ->
    shuffle(shuffle(Deck), Times-1).

% hand(7*Card) -- gives best combination with details
% {royal_flush, the_best}
% {straight_flush, queen}
% {four_of_kind, ten}
% {full_house, {king, two}}
% {flush, [ace, queen, jack, three, two]}
% {straight, king}
% {three_of_kind, five}
% {two_pair, [nine, seven])
% {one_pair, jack}
% {high_card, not_so_good}
hand(Cards) ->
    C = combinations(Cards),
    FlushRanks = proplists:get_value(flush, C),
    StraightRanks = proplists:get_value(straight, C),
    TopThreeRank = proplists:get_value(three_of_kind, C),
    TopPairRank = proplists:get_value(pair, C),
    Pairs = proplists:get_all_values(pair, C),
    FourRankTuple = proplists:lookup(four_of_kind, C),
    if
        FlushRanks /= undefined andalso StraightRanks /= undefined
            andalso FlushRanks == StraightRanks ->
            if
                hd(FlushRanks) == ace -> {royal_flush, the_best};
                true -> {straight_flush, hd(FlushRanks)}
            end;
        FourRankTuple /= none -> FourRankTuple;
        TopThreeRank /= undefined andalso TopPairRank /= undefined ->
            {full_house, {TopThreeRank, TopPairRank}};
        FlushRanks /= undefined -> {flush, FlushRanks};
        StraightRanks /= undefined -> {straight, hd(StraightRanks)};
        TopThreeRank /= undefined -> {three_of_kind, TopThreeRank};
        length(Pairs) >= 2 -> {two_pair, lists:sublist(Pairs, 2)};
        TopPairRank /= undefined -> {one_pair, TopPairRank};
        true -> {high_card, not_so_good}
    end.

% combinations(7*Card) -- gives proplist of combinations met
% [..., {flush, [ace, queen, jack, ten, two]}, ...] % ranks sorted
% [..., {straight, [queen, jack, ten, nine, eight]}, ...] % ranks sorted
% [..., {four_of_kind, queen}, ...]
% [..., {three_of_kind, queen}, ...] % multiply tuples sorted: highest first
% [..., {pair, queen}, ...] % multiply tuples sorted: highest first
combinations(Cards) ->
    {SuitMatch, RankMatch} =
        lists:foldl(
            fun ({Suit, Rank}, {SuitAcc, RankAcc}) ->
                {lists:map(
                    fun ({S1, L1}) when S1 == Suit -> {Suit, [Rank | L1]};
                        (X1) -> X1
                    end,
                    SuitAcc),
                 lists:map(
                    fun ({R1, C1}) when R1 == Rank -> {Rank, C1+1};
                        (Y1) -> Y1
                    end,
                    RankAcc)}
            end,
            {[{S, []} || S <- suits()], [{R, 0} || R <- ranks()]},
            Cards),
    lists:flatmap(
        fun ({_, L2}) when length(L2) >= 5 -> [{flush, lists:sublist(rank_sort(L2), 5)}];
            (_) -> []
        end,
        SuitMatch)
    ++ lists:sort(
        fun ({_, R11}, {_, R12}) -> rank_compare(R11, R12)
        end,
        lists:flatmap(
            fun ({R2, 4}) -> [{four_of_kind, R2}];
                ({R2, 3}) -> [{three_of_kind, R2}];
                ({R2, 2}) -> [{pair, R2}];
                (_) -> []
            end,
            RankMatch))
    ++ straight(lists:sort(
        fun rank_compare/2,
        lists:flatmap(
            fun ({_, 0}) -> [];
                ({R3, _}) -> [R3]
            end,
            RankMatch))).

straight([ace | Ranks]) ->
    straight([ace | Ranks] ++ [ace], ranks() ++ [ace], 0, []);
straight(Ranks) ->
    straight(Ranks, ranks(), 0, []).

straight([R | Ranks], [R | AllRanks], Seq, []) ->
    straight(Ranks, AllRanks, Seq+1, [R]);
straight(_, _, 5, ReversedRanks) ->
    [{straight, lists:reverse(ReversedRanks)}];
straight([R | Ranks], [R | AllRanks], Seq, ReversedRanks) ->
    straight(Ranks, AllRanks, Seq+1, [R | ReversedRanks]);
straight([R | Ranks], [AR | AllRanks], Seq, ReversedRanks) ->
    case rank_compare(R, AR) of
        true -> straight(Ranks, [AR | AllRanks], Seq, ReversedRanks);
        false -> straight([R | Ranks], AllRanks, 0, [])
    end;
straight(_, _, _, _) ->
    [].

rank_compare(R, R) -> false;
rank_compare(A, B) -> rank_compare(A, B, ranks()).

rank_compare(R, _, [R | _]) -> true;
rank_compare(_, R, [R | _]) -> false;
rank_compare(A, B, [_ | Ranks]) -> rank_compare(A, B, Ranks).

rank_sort(Ranks) ->
    lists:sort(fun rank_compare/2, Ranks).

hand_compare(CardsL, CardsR) ->
    HandL = hand(CardsL),
    HandR = hand(CardsR),
    hand_compare(HandL, HandR, hands(), CardsL, CardsR).

hand_compare({H, DL}, {H, DR}, _, CardsL, CardsR) ->
    case H of
        straight_flush when DL == DR -> equal;
        straight_flush -> hand_compare_rank(DL, DR);
        four_of_kind when DL == DR -> hand_compare_exclude(CardsL, CardsR, [DL], 1);
        four_of_kind -> hand_compare_rank(DL, DR);
        full_house when DL == DR -> equal;
        full_house ->
            if
                element(1, DL) == element(1, DR) ->
                    hand_compare_rank(element(2, DL), element(2, DR));
                true -> hand_compare_rank(element(1, DL), element(1, DR))
            end;
        flush when DL == DR -> equal;
        flush -> hand_compare_exclude(DL, DR, 5, ranks_only);
        straight when DL == DR -> equal;
        straight -> hand_compare_rank(DL, DR);
        three_of_kind when DL == DR -> hand_compare_exclude(CardsL, CardsR, [DL], 2);
        three_of_kind -> hand_compare_rank(DL, DR);
        two_pair when DL == DR -> hand_compare_exclude(CardsL, CardsR, DL, 1);
        two_pair ->
            if
                hd(DL) == hd(DR) ->
                    hand_compare_rank(lists:nth(2, DL), lists:nth(2, DR));
                true -> hand_compare_rank(hd(DL), hd(DR))
            end;
        one_pair when DL == DR -> hand_compare_exclude(CardsL, CardsR, [DL], 3);
        one_pair -> hand_compare_rank(DL, DR);
        high_card -> hand_compare_exclude(CardsL, CardsR, [], 5);
        _ -> equal
    end;
hand_compare({H, _}, _, [H | _], _, _) -> left;
hand_compare(_, {H, _}, [H | _], _, _) -> right;
hand_compare(HandL, HandR, [_ | Hands], _, _) ->
    hand_compare(HandL, HandR, Hands, undefined, undefined).

hand_compare_rank(RL, RR) ->
    case rank_compare(RL, RR) of
        true -> left;
        false -> right
    end.

hand_compare_exclude(_, _, 0, ranks_only) -> equal;
hand_compare_exclude([R | RanksL], [R | RanksR], CardsToCompare, ranks_only) ->
    hand_compare_exclude(RanksL, RanksR, CardsToCompare-1, ranks_only);
hand_compare_exclude([RL | _], [RR | _], _, ranks_only) ->
    hand_compare_rank(RL, RR);
hand_compare_exclude(CardsL, CardsR, ExcludeRankList, CardsToCompare) ->
    hand_compare_exclude(
        rank_sort([R || {_, R} <- CardsL, not lists:member(R, ExcludeRankList)]),
        rank_sort([R || {_, R} <- CardsR, not lists:member(R, ExcludeRankList)]),
        CardsToCompare,
        ranks_only).

test_hand() ->
    D = shuffle(deck()),
    Cards = lists:sublist(D, 7),
    io:format("Cards: ~p~nHand: ~p~n", [Cards, hand(Cards)]).

test_hand_compare() ->
    D = shuffle(deck()),
    Mutual = lists:sublist(D, 5),
    Left = lists:sublist(D, 6, 2),
    Right = lists:sublist(D, 8, 2),
    io:format("Mutual: ~p~nLeft: ~p~nRight: ~p~nCompared: ~p~n", [Mutual, Left, Right, hand_compare(Left ++ Mutual, Right ++ Mutual)]).

test_hand_compare_exact() ->
    Mutual = [{diamonds,ten}, {spades,nine}, {diamonds,eight}, {clubs,three}, {spades,two}],
    Left = [{hearts,ace},{spades,ace}],
    Right = [{spades,ace},{diamonds,queen}],
    io:format("Mutual: ~p~nLeft: ~p~nRight: ~p~nCompared: ~p~n", [Mutual, Left, Right, hand_compare(Left ++ Mutual, Right ++ Mutual)]).

hidden_game() ->
    D = shuffle(deck()),
    Mutual = lists:sublist(D, 5),
    Left = lists:sublist(D, 6, 2),
    Right = lists:sublist(D, 8, 2),
    hand_compare(Left ++ Mutual, Right ++ Mutual).

multiplayer_compare(Mutual, Winners, Candidate) ->
    case hand_compare(element(2,hd(Winners)) ++ Mutual, element(2,Candidate) ++ Mutual) of
        left -> Winners;
        right -> [Candidate];
        equal -> [Candidate | Winners]
    end.

multiplayer_game(Mutual, Hands) ->
    NumHands = lists:zip(lists:seq(1, length(Hands)), Hands),
    lists:foldl(fun(C,W) -> multiplayer_compare(Mutual, W, C) end, [hd(NumHands)], tl(NumHands)).

multi_game(Mutual, Hands) ->
    proplists:get_keys(multiplayer_game(Mutual, Hands)).

stat_block(_, Cycles, Cycles, Success) ->
    Success/Cycles;
stat_block(F, Cycles, Iter, Success) ->
    case F() of
        true -> stat_block(F, Cycles, Iter+1, Success+1);
        _ -> stat_block(F, Cycles, Iter+1, Success)
    end.

stat_multi_game_one(Mine, Mutual, Num) ->
    D = lists:subtract(shuffle(deck()), Mine),
    {Mutual1, D1} = case Mutual of 
        [] -> {lists:sublist(D, 5), lists:sublist(D, 6, length(D) - 2 - 5)};
        _ -> {Mutual, lists:substract(D, Mutual)}
    end,
    Hands = [lists:sublist(D1, 8 + K, 2) || K <- lists:seq(0, Num*2 - 4, 2)],
    multi_game(Mutual1, [Mine | Hands]).

stat_multi_game(Mine, Mutual, Num) ->
    stat_block(fun() -> lists:member(1,stat_multi_game_one(Mine, Mutual, Num)) end, 10000, 0, 0).

test_speed_cycle(Fun, Quantity) ->
    Fun(),
    receive
        {my_timer, checkpoint} ->
            io:format("~p times~n", [Quantity])
    after 0 ->
        test_speed_cycle(Fun, Quantity+1)
    end.

test_speed(Seconds, Fun) ->
    timer:start(),
    timer:send_after(Seconds*1000, {my_timer, checkpoint}),
    test_speed_cycle(Fun, 0).

test_speed_hidden_game(Seconds) ->
    test_speed(Seconds, fun hidden_game/0).

test_random_multiplayer(Num) ->
    D = shuffle(deck()),
    Mutual = lists:sublist(D, 5),
    Hands = [lists:sublist(D, 6 + K, 2) || K <- lists:seq(0, Num*2 - 2, 2)],
    io:format("Mutual: ~p~nHands: ~p~n", [Mutual, Hands]),
    io:format("Result: ~p~n", [multiplayer_game(Mutual, Hands)]).

