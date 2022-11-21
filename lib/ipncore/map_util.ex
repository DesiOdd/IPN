defmodule MapUtil do
  alias Ipncore.Address
  ## util functions
  def to_keywords(params) do
    Enum.map(params, fn {k, v} -> {k, v} end)
  end

  def to_atom_keywords(params) do
    Enum.map(params, fn {k, v} -> {String.to_atom(k), v} end)
  end

  def to_keywords(map, filter) do
    map
    |> Map.take(filter)
    |> Enum.map(fn {k, v} -> {k, v} end)
  end

  def to_atoms(map) do
    for {k, v} <- map, into: %{}, do: {String.to_atom(k), v}
  end

  def to_atoms(map, filter) do
    for {k, v} <- Map.take(map, filter), into: %{}, do: {String.to_atom(k), v}
  end

  def drop_nils(map) do
    for {k, v} when v <- map != nil, into: %{}, do: {k, v}
  end

  ## Validation functions
  def validate_not_empty(nil), do: throw("Error value is empty")
  def validate_not_empty(%{}), do: throw("Error value is empty")
  def validate_not_empty(map), do: map

  def validate_email(map, key) do
    email = Map.get(map, key)

    if !is_nil(email) and not Regex.match?(Const.Regex.email(), email),
      do: throw("Invalid #{key}")

    map
  end

  def validate_hostname(map, key) do
    val = Map.get(map, key)
    if val and not Regex.match?(Const.Regex.hostname(), val), do: throw("Invalid #{key}")

    map
  end

  def validate_address(map, key) do
    val = Map.get(map, key)
    if val and not Regex.match?(Const.Regex.address(), val), do: throw("Invalid address #{key}")
    map
  end

  def validate_format(map, key, regex) do
    val = Map.get(map, key)
    if val and not Regex.match?(regex, val), do: throw("Invalid #{key}")

    map
  end

  def validate_boolean(map, key, :boolean) do
    val = Map.get(map, key)
    if val and not is_boolean(val), do: throw("Invalid #{key}")
    map
  end

  def validate_integer(map, key) do
    val = Map.get(map, key)
    if val and not is_integer(val), do: throw("Invalid #{key}")
    map
  end

  def validate_value(map, key, op, value) do
    val = Map.get(map, key)

    (val &&
       case op do
         :gt -> val > value
         :eq -> val == value
         :lt -> val < value
         :gte -> val >= value
         :lte -> val <= value
       end)
    |> case do
      true ->
        throw("Invalid #{key}")

      false ->
        map
    end
  end

  def validate_range(map, key, range) do
    val = Map.get(map, key)
    if val not in range, do: throw("Invalid range #{key}")
    map
  end

  def require_only(map, keys) do
    result = Enum.all?(Map.keys(map), fn x -> x in keys end)

    if not result, do: throw("Error check require values")
    map
  end

  def validate_bytes(map, key, _x.._y = range) do
    val = Map.get(map, key)
    if byte_size(val) not in range, do: throw("Invalid max length #{key}")

    map
  end

  def validate_bytes(map, key, size, _) do
    val = Map.get(map, key)
    if byte_size(val) > size, do: throw("Invalid max length #{key}")

    map
  end

  def validate_length(map, key, _x.._y = range) do
    val = Map.get(map, key)
    if String.length(val) not in range, do: throw("Invalid max length #{key}")

    map
  end

  def validate_length(map, key, size, _) do
    val = Map.get(map, key)
    if String.length(val) > size, do: throw("Invalid max length #{key}")

    map
  end

  ## Encode/Decode functions
  def decode_address(map, key) do
    val = Map.get(map, key)
    Map.put(map, key, Address.from_text(val))
  end

  def encode_address(map, key) do
    val = Map.get(map, key)
    Map.put(map, key, Address.to_text(val))
  end
end