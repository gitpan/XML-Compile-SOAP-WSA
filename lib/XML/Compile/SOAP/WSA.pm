# Copyrights 2010 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::WSA;
use vars '$VERSION';
$VERSION = '0.10';

use base 'XML::Compile::SOAP::Extension';

use Log::Report 'xml-compile-soap-wsa';

use XML::Compile::SOAP::WSA::Util qw/WSA10MODULE WSA09 WSA10 WSDL11WSAW/;

use File::Spec              ();
use File::Basename          qw/dirname/;

my @common_hdr_elems = qw/To From Action ReplyTo FaultTo MessageID
  RelatesTo RetryAfter/;
my @wsa09_hdr_elems  = (@common_hdr_elems, qw/ReplyAfter/);
my @wsa10_hdr_elems  = (@common_hdr_elems, qw/ReferenceParameters/);

my %versions =
  ( '0.9' => { xsd => '20070619-wsa09.xsd', wsa => WSA09
             , hdr => \@wsa09_hdr_elems }
  , '1.0' => { xsd => '20080723-wsa10.xsd', wsa => WSA10
             , hdr => \@wsa10_hdr_elems }
  );


sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);
    my $version = $args->{version}
        or error __x"explicit wsa_version required";
    trace "initializing wsa $version";

    $version = '1.0' if $version eq WSA10MODULE;
    $versions{$version}
        or error __x"unknown wsa version {v}, pick from {vs}"
             , v => $version, vs => [keys %versions];
    $self->{version} = $version;
    $self;
}

#-----------


sub version() {shift->{version}}
sub wsaNS()   {$versions{shift->{version}}{wsa}}

#-----------


sub _load_ns($$)
{   my ($self, $schema, $fn) = @_;
    my $xsd = File::Spec->catfile(dirname(__FILE__), 'WSA', 'xsd', $fn);
    $schema->importDefinitions($xsd);
}

sub wsdl11Init($@)
{   my ($self, $wsdl, $args) = @_;
    my $def = $versions{$self->{version}};

    my $ns = $self->wsaNS;
    $wsdl->prefixes(wsa => $ns, wsaw => WSDL11WSAW);

    trace "loading wsa $self->{version}";
    $self->_load_ns($wsdl, $def->{xsd});
    $self->_load_ns($wsdl, '20060512-wsaw.xsd');

    # For unknown reason, the FaultDetail header is described everywhere,
    # except in the schema.
    $wsdl->importDefinitions( <<_FAULTDETAIL );
<schema xmlns="http://www.w3.org/2001/XMLSchema"
     xmlns:tns="$ns" targetNamespace="$ns"
     elementFormDefault="qualified"
     attributeFormDefault="unqualified">
  <element name="FaultDetail">
    <complexType>
      <sequence>
        <any minOccurs="0" maxOccurs="unbounded" />
      </sequence>
    </complexType>
  </element>
</schema>
_FAULTDETAIL

   $self;
}

sub soap11OperationInit($@)
{   my ($self, $op, %args) = @_;
    my $ns = $self->wsaNS;

    trace "adding wsa header logic";
    my $def = $versions{$self->{version}};
    foreach my $hdr ( @{$def->{hdr}} )
    {   $op->addHeader(INPUT  => "wsa_$hdr" => "{$ns}$hdr");
        $op->addHeader(OUTPUT => "wsa_$hdr" => "{$ns}$hdr");
    }

    # soap11 specific
    $op->addHeader(OUTPUT => wsa_FaultDetail => "{$ns}FaultDetail");
}

sub soap11ClientWrapper($$@)
{   my ($self, $op, $call, %args) = @_;
    my $to     = $args{To}     || ($op->endPoints)[0];
    my $action = $args{Action} || $op->soapAction;

    trace "added wsa in call $to for $action";
    sub
    {   $call->(wsa_To => $to, wsa_Action => $action, @_);
    };
}


1;
