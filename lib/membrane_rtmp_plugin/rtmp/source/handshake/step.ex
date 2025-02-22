defmodule Membrane.RTMP.Handshake.Step do
  @moduledoc false

  # Describes steps in the process of RTMP handshake

  @enforce_keys [:data, :type]
  defstruct @enforce_keys

  @typedoc """
  RTMP handshake types.

  The handshake flow between client and server looks as follows:

   +-------------+                            +-------------+
   |   Client    |        TCP/IP Network      |    Server   |
   +-------------+             |              +-------------+
          |                    |                     |
   Uninitialized               |               Uninitialized
          |           C0       |                     |
          |------------------->|         C0          |
          |                    |-------------------->|
          |           C1       |                     |
          |------------------->|         S0          |
          |                    |<--------------------|
          |                    |         S1          |
    Version sent               |<--------------------|
          |           S0       |                     |
          |<-------------------|                     |
          |           S1       |                     |
          |<-------------------|                Version sent
          |                    |         C1          |
          |                    |-------------------->|
          |           C2       |                     |
          |------------------->|         S2          |
          |                    |<--------------------|
       Ack sent                |                  Ack Sent
          |           S2       |                     |
          |<-------------------|                     |
          |                    |         C2          |
          |                    |-------------------->|
    Handshake Done             |              Handshake Done
          |                    |                     |

  Where `C0` and `S0` are RTMP protocol version (set to 0x03).

  Both sides exchange random chunks of 1536 bytes and the other side is supposed to
  respond with those bytes remaining unchanged.

  In case of `S1` and `S2`, the latter is supposed to be equal to `C1` while
  the client has to respond by sending `C2` with the `S1` as the value.
  """
  @type handshake_type_t :: :c0_c1 | :s0_s1_s2 | :c2

  @type t :: %__MODULE__{
          data: binary(),
          type: handshake_type_t()
        }

  @rtmp_version 0x03

  @handshake_size 1536
  @s1_s2_size 2 * @handshake_size

  defmacrop invalid_step_error(type) do
    quote do
      {:error, {:invalid_handshake_step, unquote(type)}}
    end
  end

  @doc """
  Serializes the step.
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{type: type, data: data}) when type in [:c0_c1, :s0_s1_s2] do
    <<@rtmp_version, data::binary>>
  end

  def serialize(%__MODULE__{data: data}), do: data

  @doc """
  Deserializes the handshake step given the type.
  """
  @spec deserialize(handshake_type_t(), binary()) ::
          {:ok, t()} | {:error, :invalid_handshake_step}
  def deserialize(:c0_c1 = type, <<0x03, data::binary-size(@handshake_size)>>) do
    {:ok, %__MODULE__{type: type, data: data}}
  end

  def deserialize(:s0_s1_s2 = type, <<0x03, data::binary-size(@s1_s2_size)>>) do
    {:ok, %__MODULE__{type: type, data: data}}
  end

  def deserialize(:c2 = type, <<data::binary-size(@handshake_size)>>) do
    {:ok, %__MODULE__{type: type, data: data}}
  end

  def deserialize(_type, _data), do: {:error, :invalid_handshake_step}

  @doc """
  Verifies if the following handshake step matches the previous one.

  C1 should have the same value as S2 and C2 be the same as  S1.
  """
  @spec verify_next_step(t() | nil, t()) ::
          :ok | {:error, {:invalid_handshake_step, handshake_type_t()}}
  def verify_next_step(previous_step, next_step)

  def verify_next_step(nil, %__MODULE__{type: :c0_c1}), do: :ok

  def verify_next_step(%__MODULE__{type: :c0_c1, data: c1}, %__MODULE__{
        type: :s0_s1_s2,
        data: s1_s2
      }) do
    <<_s1::binary-size(@handshake_size), s2::binary-size(@handshake_size)>> = s1_s2

    if s2 == c1 do
      :ok
    else
      invalid_step_error(:s0_s1_s2)
    end
  end

  def verify_next_step(%__MODULE__{type: :s0_s1_s2, data: s1_s2}, %__MODULE__{type: :c2, data: c2}) do
    <<s1::binary-size(@handshake_size), _s2::binary>> = s1_s2

    if c2 == s1 do
      :ok
    else
      invalid_step_error(:c2)
    end
  end

  @doc """
  Returns epoch timestamp of the connection.
  """
  @spec epoch(t()) :: non_neg_integer()
  def epoch(%__MODULE__{data: <<epoch::32, _rest::binary>>}), do: epoch
end
