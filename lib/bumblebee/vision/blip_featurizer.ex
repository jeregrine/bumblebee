defmodule Bumblebee.Vision.BlipFeaturizer do
  alias Bumblebee.Shared

  options = [
    resize: [
      default: true,
      doc: "whether to resize (and optionally center crop) the input to the given `:size`"
    ],
    size: [
      default: 384,
      doc: """
      the size to resize the input to. Either a single number or a `{height, width}` tuple.
      Only has an effect if `:resize` is `true`
      """
    ],
    resize_method: [
      default: :bicubic,
      doc:
        "the resizing method, either of `:nearest`, `:bilinear`, `:bicubic`, `:lanczos3`, `:lanczos5`"
    ],
    normalize: [
      default: true,
      doc: "whether or not to normalize the input with mean and standard deviation"
    ],
    image_mean: [
      default: [0.48145466, 0.4578275, 0.40821073],
      doc: "the sequence of mean values for each channel, to be used when normalizing images"
    ],
    image_std: [
      default: [0.26862954, 0.26130258, 0.27577711],
      doc:
        "the sequence of standard deviations for each channel, to be used when normalizing images"
    ]
  ]

  @moduledoc """
  BLIP featurizer for image data.

  ## Configuration

  #{Shared.options_doc(options)}
  """

  defstruct Shared.option_defaults(options)

  @behaviour Bumblebee.Featurizer
  @behaviour Bumblebee.Configurable

  alias Bumblebee.Utils.Image

  @impl true
  def config(featurizer, opts \\ []) do
    Shared.put_config_attrs(featurizer, opts)
  end

  @impl true
  def apply(featurizer, images, _defn_options) do
    images = List.wrap(images)

    images =
      for image <- images do
        images =
          image
          |> Image.to_batched_tensor()
          |> Nx.as_type(:f32)
          |> Image.normalize_channels(length(featurizer.image_mean))

        if featurizer.resize do
          size = Image.normalize_size(featurizer.size)
          NxImage.resize(images, size, method: featurizer.resize_method)
        else
          images
        end
      end
      |> Nx.concatenate()

    images = NxImage.to_continuous(images, 0, 1)

    images =
      if featurizer.normalize do
        NxImage.normalize(
          images,
          Nx.tensor(featurizer.image_mean),
          Nx.tensor(featurizer.image_std)
        )
      else
        images
      end

    %{"pixel_values" => images}
  end

  defimpl Bumblebee.HuggingFace.Transformers.Config do
    def load(featurizer, data) do
      import Shared.Converters

      opts =
        convert!(data,
          resize: {"do_resize", boolean()},
          size: {"size", one_of([number(), size_as_map()])},
          resize_method: {"resample", resize_method()},
          normalize: {"do_normalize", boolean()},
          image_mean: {"image_mean", list(number())},
          image_std: {"image_std", list(number())}
        )

      @for.config(featurizer, opts)
    end

    defp size_as_map() do
      fn name, value ->
        case value do
          %{"height" => height, "width" => width} ->
            {:ok, {height, width}}

          _ ->
            {:error,
             "expected #{inspect(name)} to be a map with height and width, got: #{inspect(value)}"}
        end
      end
    end
  end
end
