# Makefile.am for add-on/src

yncludedir = @yncludedir@/add-on

client_DATA =			 \
	add-on.ycp		 \
	add-on_auto.ycp		 \
	add-on_proposal.ycp	 \
	inst_add-on.ycp		 \
	inst_language_add-on.ycp \
	vendor.ycp

ynclude_DATA =			\
	add-on-workflow.ycp

desktop_DATA =			\
	add-on.desktop		\
	vendor.desktop

module_DATA =			\
	AddOnProduct.ycp

# create a symlink for local build, #145327
add-on:
	ln -sf . $@
ycpchook = add-on

rncdir =  $(schemadir)/autoyast/rnc
rnc_DATA = add-on.rnc

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(module_DATA) $(desktop_DATA) $(rnc_DATA)

include $(top_srcdir)/Makefile.am.common
