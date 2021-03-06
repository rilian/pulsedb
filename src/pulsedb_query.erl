-module(pulsedb_query).
-export([parse/1,render/1]).
-export([name/1, set_name/2]).
-export([tag/2, remove_tag/2, add_tag/2]).
-export([set_range/3, downsampler/1, downsampler_step/1, set_step/2]).

-record(query, {
  aggregator,
  downsampler,
  name,
  tags = []
 }).

parse(Query) ->
  {A,D,N,T} = pulsedb_parser:parse(Query),
  #query{aggregator=A, downsampler=D, name=N, tags=lists:sort(T)}.


render(undefined) -> 
  undefined;

render(#query{aggregator=Aggregator,
              downsampler=Downsampler,
              name=Name, tags=Tags}) ->
  Parts = [
    case Aggregator of
      undefined -> <<>>;
      _ -> <<Aggregator/binary, ":">>
    end,
    case Downsampler of
      {N_,Fn} ->
        N = integer_to_binary(N_),
        <<N/binary,"s-",Fn/binary,":">>;
      _ -> <<>>
    end,
    Name,
    tags_to_text(Tags)],
  iolist_to_binary(Parts).


name(#query{name=Name}) -> 
  Name.

set_name(Name, #query{}=Q) ->
  Q#query{name=Name}.


set_range(From0, To0, #query{}=Q) when is_number(From0), is_number(To0) ->
  Step = downsampler_step(Q),
  case Step of
    1 ->
      add_tag([{from, From0}, {to, To0}], Q);
    _ ->
      To   = ((To0 div Step) - 1)*Step - 1,
      From = case From0 - (From0 rem Step) of
               Value when Value > To -> Value - Step;
               Value                 -> Value
             end,
      add_tag([{from, From}, {to, To}], Q)
  end.

downsampler(#query{downsampler=Downsampler}) ->
  case Downsampler of
    {_,DS} -> DS;
    _ -> undefined
  end.

downsampler_step(#query{downsampler=Downsampler}) ->
  case Downsampler of
    {S,_} -> S;
    undefined -> 1
  end.


set_step(Step, #query{aggregator=Aggregator, downsampler=Downsampler}=Q) when is_number(Step) ->
  case {Aggregator, Downsampler} of
    {A, {_, Fn}} when is_binary(A) ->
      Q#query{downsampler={Step, Fn}};
    _ ->
      Q#query{aggregator= <<"sum">>, downsampler={Step, <<"avg">>}}
  end.


tag(Tag, #query{tags=Tags}) ->
  proplists:get_value(Tag, Tags).


add_tag(Tags, #query{}=Query) when is_list(Tags) ->
  lists:foldl(fun add_tag/2, Query, Tags);

add_tag({Tag,_}=T, #query{tags=Tags0}=Q) ->
  Tags = lists:keystore(Tag, 1, Tags0, T),
  Q#query{tags=Tags}.


remove_tag(Tags, #query{}=Query) when is_list(Tags) ->
  lists:foldl(fun remove_tag/2, Query, Tags);

remove_tag(Tag, #query{tags=Tags0}=Q) ->
  Tags = lists:keydelete(Tag, 1, Tags0),
  Q#query{tags=Tags}.



tags_to_text([]) -> <<>>;
tags_to_text(Tags_) ->
  Tags = tags_to_text0(Tags_),
  <<"{", Tags/binary, "}">>.

tags_to_text0([Tag0]) -> tag_to_text(Tag0);
tags_to_text0([Tag0|Rest0]) ->
  Tag = tag_to_text(Tag0),
  Rest = tags_to_text0(Rest0),
  <<Tag/binary, ",", Rest/binary>>.

tag_to_text({Tag, Value}) when is_atom(Tag) ->
  tag_to_text({atom_to_binary(Tag, latin1), Value});
tag_to_text({Tag, Value}) when is_binary(Tag) ->
  iolist_to_binary([Tag, "=", value_to_text(Value)]).


value_to_text(Value) when is_number(Value) ->
  integer_to_binary(Value);
value_to_text(Value) when is_atom(Value) ->
  atom_to_binary(Value, latin1);
value_to_text(Value) ->
  Value.
