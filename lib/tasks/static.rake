desc "Generate a static HTML site from published books into DIR (default: tmp/static-site). " \
     "Set STATIC_HOST for absolute URLs; STATIC_ALL=1 to include unpublished books."
namespace :static do
  task :generate, [:dir] => :environment do |_task, args|
    dir = args[:dir] || "tmp/static-site"
    host = ENV.fetch("STATIC_HOST", "example.com")

    if ENV["STATIC_ALL"] == "1"
      # Temporarily publish every book so the exporter renders it, then roll the
      # change back so the live database is left untouched.
      Book.transaction do
        Book.where(published: [false, nil]).update_all(published: true)
        Writebook::StaticExporter.new(dir, host: host, verbose: true).call
        raise ActiveRecord::Rollback
      end
    else
      Writebook::StaticExporter.new(dir, host: host, verbose: true).call
    end
  end
end