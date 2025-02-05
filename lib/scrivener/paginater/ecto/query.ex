defimpl Scrivener.Paginater, for: Ecto.Query do
  import Ecto.Query

  alias Scrivener.{Config, Page, SimplePage}

  @moduledoc false

  @spec paginate(Ecto.Query.t(), Scrivener.Config.t()) ::
          Scrivener.Page.t() | Scrivener.SimplePage.t()
  def paginate(query, %Config{
        page_type: :normal,
        module: repo,
        caller: caller,
        page_number: page_number,
        page_size: page_size,
        options: options
      }) do
    total_entries =
      options
      |> Keyword.put_new(:caller, caller)
      |> Keyword.get_lazy(:total_entries, fn ->
        aggregate(query, repo, options)
      end)

    total_pages = total_pages(total_entries, page_size)
    allow_overflow_page_number = Keyword.get(options, :allow_overflow_page_number, false)

    page_number =
      if allow_overflow_page_number, do: page_number, else: min(total_pages, page_number)

    entries =
      if page_number > total_pages,
        do: [],
        else: entries(query, repo, page_number, page_size, options)

    %Page{
      page_size: page_size,
      page_number: page_number,
      entries: entries,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  def paginate(query, %Config{
        page_type: :simple,
        module: repo,
        page_number: page_number,
        page_size: page_size,
        options: options
      }) do
    entries_with_maybe_one_extra =
      entries(query, repo, page_number, page_size, options, extra_entry_size: 1)

    {entries, has_more} =
      if length(entries_with_maybe_one_extra) > page_size do
        entries =
          entries_with_maybe_one_extra
          |> Enum.reverse()
          |> tl()
          |> Enum.reverse()

        {entries, true}
      else
        {entries_with_maybe_one_extra, false}
      end

    %SimplePage{
      page_size: page_size,
      page_number: page_number,
      entries: entries,
      has_more: has_more
    }
  end

  defp entries(query, repo, page_number, page_size, options, opts \\ []) do
    extra_entry_size = Keyword.get(opts, :extra_entry_size, 0)
    offset = Keyword.get_lazy(options, :offset, fn -> page_size * (page_number - 1) end)
    limit = page_size + extra_entry_size

    query
    |> offset(^offset)
    |> limit(^limit)
    |> repo.all(options)
  end

  defp aggregate(
         %{
           group_bys: [
             %{
               expr: [
                 {{:., [], [{:&, [], [source_index]}, field]}, [], []} | _
               ]
             }
             | _
           ]
         } = query,
         repo,
         options
       ) do
    query
    |> exclude(:preload)
    |> exclude(:order_by)
    |> exclude(:select)
    |> select([{x, source_index}], struct(x, ^[field]))
    |> subquery()
    |> select(count("*"))
    |> repo.one(options)
  end

  defp aggregate(query, repo, options) do
    repo.aggregate(query, :count, options)
  end

  defp total_pages(0, _), do: 1

  defp total_pages(total_entries, page_size) do
    (total_entries / page_size) |> Float.ceil() |> round
  end
end
