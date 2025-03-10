package TheSchwartz::Moosified::Utils;

use base 'Exporter';
use Carp;
use Scalar::Util qw(blessed);
use vars qw/@EXPORT_OK/;

@EXPORT_OK = qw/insert_id sql_for_unixtime bind_param_attr run_in_txn
                order_by_priority sql_for_where_not_exists
                coerce_dbh_from_connect_strings/;

sub insert_id {
    my ( $dbh, $sth, $table, $col ) = @_;

    my $driver = $dbh->{Driver}{Name};
    if ( $driver eq 'mysql' ) {
        return $dbh->{mysql_insertid};
    }
    elsif ( $driver eq 'Pg' ) {
        return $dbh->last_insert_id( undef, undef, undef, undef,
            { sequence => join( "_", $table, $col, 'seq' ) } );
    }
    elsif ( $driver eq 'SQLite' ) {
        return $dbh->func('last_insert_rowid');
    }
    else {
        croak "Don't know how to get last insert id for $driver";
    }
}

# SQL doesn't define a function to ask a machine of its time in
# unixtime form.  MySQL does
# but for sqlite and others, we assume "remote" time is same as local
# machine's time, which is especially true for sqlite.
sub sql_for_unixtime {
    my ($dbh) = @_;
    
    my $driver = $dbh->{Driver}{Name};
    if ( $driver and $driver eq 'mysql' ) {
        return "UNIX_TIMESTAMP()";
    }
    if ( $driver and $driver eq 'Pg' ) {
        return "EXTRACT(EPOCH FROM NOW())::integer";
    }
    
    return time();
}

sub sql_for_where_not_exists {
    my ($dbh, $table_exitstatus) = @_;

    my $driver = $dbh->{Driver}{Name};
    if ( $driver and $driver eq 'mysql' ) {
        return qq{ FROM $table_exitstatus
                   WHERE NOT EXISTS (
                   SELECT 1 FROM $table_exitstatus WHERE jobid = ?
                   )
                   LIMIT 1 };
    } else {
        return qq{ WHERE NOT EXISTS (
                   SELECT 1 FROM $table_exitstatus WHERE jobid = ?
                   ) };

    }
}

sub bind_param_attr {
    my ( $dbh, $col ) = @_;

    return if $col ne 'arg';

    my $driver = $dbh->{Driver}{Name};
    if ( $driver and $driver eq 'Pg' ) {
        return { pg_type => DBD::Pg::PG_BYTEA() };
    }
    elsif ( $driver and $driver eq 'SQLite' ) {
        return DBI::SQL_BLOB();
    }
    return;
}

sub order_by_priority {
    my $dbh = shift;

    my $driver = $dbh->{Driver}{Name};
    if ( $driver and $driver eq 'Pg' ) {
        # make NULL sort as if it were 0, consistent with SQLite
        # Suggestion:
        # CREATE INDEX ix_job_piro_non_null ON job (COALESCE(priority,0));
        return 'ORDER BY COALESCE(priority,0) DESC';
    }
    return 'ORDER BY priority DESC';
}

sub run_in_txn (&$) {
    my $code = shift;
    my $dbh = shift;
    local $dbh->{RaiseError} = 1;

    my $need_txn = $dbh->{AutoCommit} ? 1 : 0;
    return $code->() unless $need_txn;

    my @rv;
    my $rv;
    eval {
        $dbh->begin_work;
        if (wantarray) {
            @rv = $code->();
        }
        else {
            $rv = $code->();
        }
        $dbh->commit;
    };
    if (my $err = $@) { eval { $dbh->rollback }; die $err }

    return @rv if wantarray;
    return $rv;
}

sub coerce_dbh_from_connect_strings {
    my ($connect_strings) = @_;
    my @dbhs;
    for (@$connect_strings) {
        if ( blessed $_ && $_->isa('DBI::db') ) {

            # warn "### got dbi::db already";
            push @dbhs, $_;
        } else {
            push @dbhs,
              DBI->connect(
                $_->{dsn},
                $_->{user},
                $_->{pass},
                {
                    AutoCommit => 1,
                    RaiseError => 0,
                    PrintError => 0,
                } )
              or croak
              "Databases requires ArraryRef of dbh or connect info (dsn,user,pass).";
        }
    }
    return \@dbhs;
}

1;
__END__
