# Sources for add-on

client_DATA = \
  clients/inst_language_add-on.rb \
  clients/inst_add-on_software.rb \
  clients/inst_add-on.rb \
  clients/add-on.rb \
  clients/add-on_auto.rb \
  clients/vendor.rb \
  clients/add-on_proposal.rb

yncludedir = @yncludedir@/add-on
ynclude_DATA = \
  include/add-on/misc.rb \
  include/add-on/add-on-workflow.rb

schemafilesdir = $(schemadir)/autoyast/rnc
schemafiles_DATA = \
  autoyast-rnc/add-on.rnc

desktop_DATA = \
  desktop/add-on.desktop \
  desktop/vendor.desktop

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(schemafiles_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common