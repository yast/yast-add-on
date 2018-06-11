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
Version:        4.1.0
Release:        0
Summary:        YaST2 - Add-On media installation code
License:        GPL-2.0
Group:          System/YaST
Url:            http://github.com/yast/yast-add-on
Source0:        %{name}-%{version}.tar.bz2
BuildRequires:  rubygem(%{rb_default_ruby_abi}:yast-rake)
BuildRequires:  rubygem(%{rb_default_ruby_abi}:rspec)
BuildRequires:  update-desktop-files
BuildRequires:  yast2 >= 3.0.1
BuildRequires:  yast2-devtools >= 3.1.10
BuildRequires:  yast2-packager
Requires:       autoyast2-installation
# ProductProfile
Requires:       yast2 >= 3.0.1
Requires:       yast2-country
Requires:       yast2-installation
# new AddOnProduct.DoInstall argument
Requires:       yast2-packager >= 4.0.25
Requires:       yast2-ruby-bindings >= 1.0.0

Obsoletes:      yast2-add-on-devel-doc

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildArch:      noarch

%description
This package contains YaST Add-On media installation code.

%prep
%setup -q

%check
rake test:unit

%build

%install
rake install DESTDIR=%{buildroot}

%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/add-on
%{yast_yncludedir}/add-on/*
%dir %{yast_libdir}/add-on
%dir %{yast_libdir}/add-on/clients
%{yast_libdir}/add-on/clients/*.rb
%{yast_clientdir}/add-on.rb
%{yast_clientdir}/add-on_*.rb
%{yast_clientdir}/inst_add-on*.rb
%{yast_clientdir}/vendor.rb
%{yast_desktopdir}/*.desktop
%{yast_schemadir}/autoyast/rnc/add-on.rnc
%dir %{yast_docdir}
%doc %{yast_docdir}/COPYING
%doc %{yast_docdir}/CONTRIBUTING.md
%doc %{yast_docdir}/README.md

%changelog
