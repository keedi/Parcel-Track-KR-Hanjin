package Parcel::Track::KR::Hanjin;
# ABSTRACT: Parcel::Track driver for the Hanjin (한진택배)

use utf8;

use Moo;

our $VERSION = '0.001';

with 'Parcel::Track::Role::Base';

use Encode;
use HTML::Selector::XPath;
use HTML::TreeBuilder::XPath;
use HTTP::Tiny;

#
# to support HTTPS
#
use IO::Socket::SSL;
use Mozilla::CA;
use Net::SSLeay;

our $URI =
    'https://www.hanjin.co.kr/delivery_html/inquiry/result_waybill.jsp?wbl_num=%s';

our $AGENT = 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';

sub BUILDARGS {
    my ( $class, @args ) = @_;

    my %params;
    if ( ref $args[0] eq 'HASH' ) {
        %params = %{ $args[0] };
    }
    else {
        %params = @args;
    }
    $params{id} =~ s/\D//g;

    return \%params;
}

sub uri { sprintf( $URI, $_[0]->id ) }

sub track {
    my $self = shift;

    my %result = (
        from   => q{},
        to     => q{},
        result => q{},
        htmls  => [],
        descs  => [],
    );

    my $res = HTTP::Tiny->new( agent => $AGENT )->get( $self->uri );
    unless ( $res->{success} ) {
        $result{result} = 'failed to get parcel tracking info from the site';
        return \%result;
    }

    my $content = Encode::encode( 'utf-8', Encode::decode( 'cp949', $res->{content} ) );

    unless ($content) {
        $result{result} = 'failed to tracking parcel info';
        return \%result;
    }

    #
    # http://stackoverflow.com/questions/19703341/disabling-html-entities-expanding-in-htmltreebuilder-perl-module
    #
    my $tree = HTML::TreeBuilder::XPath->new;
    $tree->ignore_unknown(0);
    $tree->no_expand_entities(1);
    $tree->attr_encoded(1);
    $tree->parse($content);
    $tree->eof;

    my ( $html1, $html2 ) = $tree->findnodes("//table");
    unless ( $html1 && $html2 ) {
        $result{result} = 'cannot find such parcel info';
        return \%result;
    }

    my $not_found = ( $tree->findnodes("//div[\@id='result_error']") )[0];
    if ($not_found) {
        $result{result} = 'cannot find such parcel info';
        return \%result;
    }

    $result{from}  = $html1->findvalue("./tbody/tr/td[4]");
    $result{to}    = $html1->findvalue("./tbody/tr/td[5]");
    $result{htmls} = [ $html1->as_HTML, $html2->as_HTML ];

    my @elements  = $html2->findnodes("./tbody/tr");
    for my $e (@elements) {
        my @tds      = $e->look_down( '_tag', 'td' );
        my @td_texts = map $self->_filter_text( $_->as_text ), @tds;

        next unless @tds == 5;

        push @{ $result{descs} }, $self->_filter_text( join( q{ }, @td_texts ) );
        $result{result} = $result{descs}->[-1];
    }

    return \%result;
}

sub _filter_text {
    my ( $self, $text ) = @_;

    $text =~ s/(^\s+|\s+$)//gms;
    $text =~ s/ +/ /gms;
    $text =~ s/^-$//;

    return $text;
}

1;

# COPYRIGHT

__END__

=for Pod::Coverage BUILDARGS

=head1 SYNOPSIS

    use Parcel::Track;

    # Create a tracker
    my $tracker = Parcel::Track->new( 'KR::Hanjin', '1234-5678-9012' );

    # ID & URI
    print $tracker->id . "\n";
    print $tracker->uri . "\n";
    
    # Track the information
    my $result = $tracker->track;
    
    # Get the information what you want.
    if ( $result ) {
        print "Message sent ok\n";
        print "$result->{from}\n";
        print "$result->{to}\n";
        print "$result->{result}\n";
        print "$_\n" for @{ $result->{descs} };
        print "$_\n" for @{ $result->{htmls} };
    }
    else {
        print "Failed to track information\n";
    }


=attr id

=method track

=method uri


=head1 SEE ALSO

=for :list
* L<Parcel::Track>
* L<Hanjin Transportation (한진택배)|https://www.hanjin.co.kr>
