
#
# Ensembl module for Bio::EnsEMBL::Compara::GenomeDB
#
# Cared for by Ewan Birney <birney@ebi.ac.uk>
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Compara::GenomeDB - DESCRIPTION of Object

=head1 SYNOPSIS

Give standard usage here

=head1 DESCRIPTION

Describe the object here

=head1 AUTHOR - Ewan Birney

This modules is part of the Ensembl project http://www.ensembl.org

Email birney@ebi.ac.uk

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::Compara::GenomeDB;
use vars qw(@ISA);
use strict;

# Object preamble - inherits from Bio::Root::RootI

use Bio::Root::RootI;
use Bio::EnsEMBL::DBLoader;

@ISA = qw(Bio::Root::RootI);

# new() is written here 

sub new {
    my($class,@args) = @_;
    
    my $self = {};
    bless $self,$class;
    
# set stuff in self from @args
    return $self;
}


=head2 db_adaptor

 Title   : db_adaptor
 Usage   :
 Function:
 Example : returns the db_adaptor
 Returns : 
 Args    :


=cut

sub db_adaptor{
   my ($self) = @_;

   if( !defined $self->{'_db_adaptor'} ) {
       # this will throw if it can't build it
       $self->{'_db_adaptor'} = Bio::EnsEMBL::DBLoader->new($self->locator);
   }

   return $self->{'_db_adaptor'};
}


=head2 locator

 Title   : locator
 Usage   : $obj->locator($newval)
 Function: 
 Example : 
 Returns : value of locator
 Args    : newvalue (optional)

=cut

sub locator{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'locator'} = $value;
    }
    return $self->{'locator'};

}

=head2 name

 Title   : name
 Usage   : $obj->name($newval)
 Function: 
 Example : 
 Returns : value of name
 Args    : newvalue (optional)


=cut

sub name{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'name'} = $value;
    }
    return $self->{'name'};

}


=head2 dbID

 Title   : dbID
 Usage   : $obj->dbID($newval)
 Function: 
 Example : 
 Returns : value of dbID
 Args    : newvalue (optional)


=cut

sub dbID{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'dbID'} = $value;
    }
    return $self->{'dbID'};

}

=head2 get_Contig

 Title   : get_Contig
 Usage   : $obj->get_Contig($newval)
 Function: 
 Example : 
 Returns : contig object
 Args    : newvalue (optional)


=cut

sub get_Contig{
   my ($self,$name,$type) = @_;

   $self->throw("Need contig name in order to fetch contig.") unless defined $name;
   $self->throw("Need contig type in order to fetch contig.") unless defined $type;

   my $contig;
   if ($type eq 'RawContig'){
      $contig = $self->db_adaptor->get_Contig($name); 
   }elsif ($type eq 'Chromosome'){
      #do we really want to be doing this.............
	  $contig = $self->db_adaptor->get_StaticGoldenPathAdaptor->fetch_VirtualContig_by_chr_name($name);
   }else {
      $self->throw ("Can't fetch contig of dnafrag with type $type");
   }

}

=head2 get_VC_by_start_end

 Title   : get_VC_by_start_end
 Usage   : $obj->get_VC_by_start_end($name,$type,$start,$end)
 Function: 
 Example : 
 Returns : contig object
 Args    : Name of Contig
           Contig type (RawContig,Chromosome)
           Start location Contig
           End location on contig


=cut

sub get_VC_by_start_end{
   my ($self,$name,$type,$start,$end) = @_;

   $self->throw("Need contig name in order to fetch contig.") unless defined $name;
   $self->throw("Need contig type in order to fetch contig.") unless defined $type;
   $self->throw("Need contig start in order to fetch contig.") unless defined $start;
   $self->throw("Need contig end in order to fetch contig.") unless defined $end;

   my $length = $end - $start +1;
   my $contig;

   if ($type eq 'RawContig'){
      $self->db_adaptor->static_golden_path_type('UCSC');
      my ($chr_name,$t_start,$t_end) = $self->db_adaptor->get_StaticGoldenPathAdaptor->get_chr_start_end_of_contig($name);

      my $chr_start = $t_start + $start -1;
      my $chr_end = $chr_start + $length -1;

      return $self->db_adaptor->get_StaticGoldenPathAdaptor->fetch_VirtualContig_by_chr_start_end ($chr_name,$chr_start,$chr_end);

   }elsif ($type eq 'Chromosome'){
	  $contig = $self->db_adaptor->get_StaticGoldenPathAdaptor->fetch_VirtualContig_by_chr_start_end($name,$start,$end);
   }else {
      $self->throw ("Can't fetch contig of dnafrag with type $type");
   }

}

1;
