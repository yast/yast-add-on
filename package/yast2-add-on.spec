#
# spec file for package yast2-add-on
#
# Copyright (c) 2016 SUSE LINUX GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-add-on
Version:        3.1.14
Release:        0
Summary:        YaST2 - Add-On media installation code
License:        GPL-2.0
Group:          System/YaST
Url:            http://github.com/yast/yast-add-on
Source0:        %{name}-%{version}.tar.bz2
BuildRequires:  rubygem(yast-rake)
BuildRequires:  update-desktop-files
BuildRequires:  yast2 >= 3.0.1
BuildRequires:  yast2-devtools >= 3.1.10
Requires:       autoyast2-installation
# ProductProfile
Requires:       yast2 >= 3.0.1
Requires:       yast2-country
Requires:       yast2-installation
# SourceDialogs.display_addon_checkbox
Requires:       yast2-packager >= 3.1.14
Requires:       yast2-ruby-bindings >= 1.0.0
# bugzilla #335582, new API for StorageDevices
Requires:       yast2-storage >= 2.16.1
# SCR::RegisterNewAgents, bugzilla #245508
Conflicts:      yast2-core < 2.15.4
# Pkg::SourceProvideSignedFile Pkg::SourceProvideDigestedFile
Conflicts:      yast2-pkg-bindings < 2.17.25
# splitted from yast2-installation
Provides:       yast2-installation:%{_datadir}/YaST2/clients/vendor.ycp
Provides:       yast2-installation:%{_datadir}/YaST2/clients/add-on.ycp
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildArch:      noarch

%description
This package contains YaST Add-On media installation code.

%package devel-doc
Summary:        YaST2 - Add-on - Development Documentation
Group:          System/YaST
Requires:       yast2-add-on = %{version}

%description devel-doc
This package contains development documentation for using the API
provided by yast2-add-on package.

%prep
%setup -q

%check
rake test:unit

%build
yardoc

%install
rake install DESTDIR=%{buildroot}

%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/add-on
%{yast_yncludedir}/add-on/*
%{yast_clientdir}/add-on.rb
%{yast_clientdir}/add-on_*.rb
%{yast_clientdir}/inst_add-on*.rb
%{yast_clientdir}/inst_*_add-on*.rb
%{yast_clientdir}/vendor.rb
%{yast_desktopdir}/*.desktop
%{yast_schemadir}/autoyast/rnc/add-on.rnc
%dir %{yast_docdir}
%doc %{yast_docdir}/COPYING
%doc %{yast_docdir}/CONTRIBUTING.md
%doc %{yast_docdir}/README.md

%files devel-doc
%defattr(-,root,root)
%doc %{yast_docdir}/autodocs

%changelog
