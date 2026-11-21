module UploadedFiles
  private
    # Active Storage attaches the signed id of an existing blob as readily as a file.
    # That id is in the URL of every file it serves, so taking one would let anyone
    # who has seen a file attach it to a book of their own and keep reading it through
    # that book after losing access to the one it came from. Writebook's forms only
    # ever submit files, so that's all an attachment param takes.
    def uploaded_file?(value)
      value.is_a?(ActionDispatch::Http::UploadedFile)
    end

    def uploaded_files_only(params, *names)
      params.reject { |name, value| name.in?(names.map(&:to_s)) && !uploaded_file?(value) }
    end
end
