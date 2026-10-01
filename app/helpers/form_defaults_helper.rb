# Every form_with renders `novalidate`, so all validation reaches the server's
# error summary (#1117). Opt out with `html: { novalidate: false }`.
module FormDefaultsHelper
  def form_with(**options, &block)
    options[:html] = { novalidate: true }.merge(options[:html] || {})
    super
  end
end
