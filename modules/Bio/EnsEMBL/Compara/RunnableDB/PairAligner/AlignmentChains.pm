=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2020] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=head1 NAME

Bio::EnsEMBL::Compara::RunnableDB::PairAligner::AlignmentChains

=head1 DESCRIPTION

Given an compara MethodLinkSpeciesSet identifer, and a reference genomic
slice identifer, fetches the GenomicAlignBlocks from the given compara
database, forms them into sets of alignment chains, and writes the result
back to the database. 

This module (at least for now) relies heavily on Jim Kent\'s Axt tools.

=cut

package Bio::EnsEMBL::Compara::RunnableDB::PairAligner::AlignmentChains;

use strict;
use warnings;

use Bio::EnsEMBL::Compara::MethodLinkSpeciesSet;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::Utils::Exception qw(throw );


use base ('Bio::EnsEMBL::Compara::Production::Analysis::AlignmentChains');


############################################################

=head2 fetch_input

    Title   :   fetch_input
    Usage   :   $self->fetch_input
    Returns :   nothing
    Args    :   none

=cut

sub fetch_input {
  my( $self) = @_; 

  $self->SUPER::fetch_input;

  my $mlssa = $self->compara_dba->get_MethodLinkSpeciesSetAdaptor;
  my $dafa = $self->compara_dba->get_DnaAlignFeatureAdaptor;
  my $gaba = $self->compara_dba->get_GenomicAlignBlockAdaptor;
  $gaba->lazy_loading(0);

  if(defined($self->param('qyDnaFragID'))) {
    my $dnafrag = $self->compara_dba->get_DnaFragAdaptor->fetch_by_dbID($self->param('qyDnaFragID'));
    $self->param('query_dnafrag', $dnafrag);
  }
  if(defined($self->param('tgDnaFragID'))) {
    my $dnafrag = $self->compara_dba->get_DnaFragAdaptor->fetch_by_dbID($self->param('tgDnaFragID'));
    $self->param('target_dnafrag', $dnafrag);
  }

  my $qy_gdb = $self->param('query_dnafrag')->genome_db;
  my $tg_gdb = $self->param('target_dnafrag')->genome_db;


  ################################################################
  # get the compara data: MethodLinkSpeciesSet, reference DnaFrag, 
  # and all GenomicAlignBlocks
  ################################################################

  my $mlss = $mlssa->fetch_by_dbID($self->param_required('input_mlss_id'))
              || throw("No MethodLinkSpeciesSet for method_link_species_set_id".$self->param('input_mlss_id'));

  my $out_mlss = $mlssa->fetch_by_dbID($self->param_required('output_mlss_id'))
              || throw("No MethodLinkSpeciesSet for method_link_species_set_id".$self->param('output_mlss_id'));

  print "mlss: ",$self->param('input_mlss_id')," ",$qy_gdb->dbID," ",$tg_gdb->dbID,"\n";

  ######## needed for output####################
  $self->param('output_MethodLinkSpeciesSet', $out_mlss);

  print STDERR "Fetching all DnaDnaAlignFeatures by query and target...\n";
  print STDERR "start fetching at time: ",scalar(localtime),"\n";

  if ($self->input_job->retry_count > 0) {
    $self->warning("Deleting alignments as it is a rerun");
    $self->delete_alignments($out_mlss,$self->param('query_dnafrag'),$self->param('target_dnafrag'));
  }

  my $gabs = $gaba->fetch_all_by_MethodLinkSpeciesSet_DnaFrag_DnaFrag($mlss,$self->param('query_dnafrag'),undef,undef,$self->param('target_dnafrag'));
  my $features;
  while (my $gab = shift @{$gabs}) {
    my ($qy_ga) = $gab->reference_genomic_align;
    my ($tg_ga) = @{$gab->get_all_non_reference_genomic_aligns};

    unless (defined $self->param('query_DnaFrag_hash')->{$qy_ga->dnafrag->name}) {
      ######### needed for output ######################################
      $self->param('query_DnaFrag_hash')->{$qy_ga->dnafrag->name} = $qy_ga->dnafrag;
    }
      
    unless (defined $self->param('target_DnaFrag_hash')->{$tg_ga->dnafrag->name}) {
      ######### needed for output #######################################
      $self->param('target_DnaFrag_hash')->{$tg_ga->dnafrag->name} = $tg_ga->dnafrag;
    }
    
    my $daf_cigar = $self->daf_cigar_from_compara_cigars($qy_ga->cigar_line,
                                                         $tg_ga->cigar_line);

    if (defined $daf_cigar) {
      my $daf = Bio::EnsEMBL::DnaDnaAlignFeature->new
        (-seqname => $qy_ga->dnafrag->name,
         -start   => $qy_ga->dnafrag_start,
         -end     => $qy_ga->dnafrag_end,
         -strand  => $qy_ga->dnafrag_strand,
         -hseqname => $tg_ga->dnafrag->name,
         -hstart  => $tg_ga->dnafrag_start,
         -hend    => $tg_ga->dnafrag_end,
         -hstrand => $tg_ga->dnafrag_strand,
         -cigar_string => $daf_cigar,
         -align_type => 'ensembl',
        );
      push @{$features}, $daf;
    }
  }
  
  $self->param('features', $features);
  print STDERR scalar @{$features}," features at time: ",scalar(localtime),"\n";

  $self->compara_dba->dbc->disconnect_if_idle();
  # Let's keep the number of connections / disconnections to the minimum
  $qy_gdb->db_adaptor->dbc->prevent_disconnect( sub {
      my $query_nib_dir = $self->param('query_nib_dir');
      # If there is no .nib file, preload the sequence
      if ($query_nib_dir and (-d $query_nib_dir) and (-e $query_nib_dir . "/" . $self->param('query_dnafrag')->name . ".nib")) {
          print STDERR "reusing the query nib file ". $query_nib_dir . "/" . $self->param('query_dnafrag')->name . ".nib" . "\n";
      } else {
          print STDERR "fetching the query sequence\n";
          my $query_slice = $self->param('query_dnafrag')->slice;
          $self->param('query_slice', $query_slice);
          $query_slice->{'seq'} = $query_slice->seq;
          print STDERR length($query_slice->{'seq'}), " bp\n";
          $self->param('query_nib_dir', undef);
      }
  } );

  $tg_gdb->db_adaptor->dbc->prevent_disconnect( sub {
      my $target_dnafrag = $self->param('target_dnafrag');
      my $target_nib_dir = $self->param('target_nib_dir');
      $self->param('target_dnafrags', {$target_dnafrag->name => $target_dnafrag});
      # If there is no .nib file, preload the sequence
      if ($target_nib_dir and (-d $target_nib_dir) and (-e $target_nib_dir . "/" . $target_dnafrag->name . ".nib")) {
          print STDERR "reusing the target nib file" . $target_nib_dir . "/" . $target_dnafrag->name . ".nib" . "\n";
      } else {
          my $target_slice = $target_dnafrag->slice;
          $self->param('target_slices', {$target_dnafrag->name => $target_slice});
          print STDERR "fetching the target sequence\n";
          $target_slice->{'seq'} = $target_slice->seq;
          print STDERR length($target_slice->{'seq'}), " bp\n";
          $self->param('target_nib_dir', undef);
      }
  } );
}



sub run{
    my ($self) = @_;

    $self->compara_dba->dbc->disconnect_if_idle();    # this one should disconnect only if there are no active kids
    my $chains = $self->run_chains;
    my $converted_chains = $self->convert_output($chains);
    $self->param('chains', $converted_chains);
}


1;
