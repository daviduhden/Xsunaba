#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use FindBin qw($RealBin);
use File::Find qw(find);
use File::Basename qw(dirname);
use File::Spec;
use Getopt::Long qw(GetOptions);

my $ROOT = File::Spec->rel2abs(File::Spec->catdir($RealBin, '..'));
my ($base, $head, $worktree);
GetOptions('base=s' => \$base, 'base-ref=s' => \$base,
           'head=s' => \$head, 'worktree' => \$worktree) or usage();
usage() if defined($base) != defined($head) && defined($head) && !$worktree;
usage() if $worktree && (defined($base) || defined($head));

sub usage {
    print STDERR "usage: $0 [--base REV [--head REV] | --base-ref REV | --worktree]\n";
    exit 2;
}

sub git {
    my (@args) = @_;
    open my $fh, '-|', 'git', '-C', $ROOT, @args or die "cannot run git: $!";
    local $/;
    my $out = <$fh> // '';
    close $fh or die "git @args failed";
    return $out;
}

sub split_nul { return grep { length } split /\0/, $_[0]; }
sub is_instruction {
    my ($p) = @_;
    return $p =~ m{(?:^|/)(?:AGENTS\.md|SKILL\.md|[^/]+\.agent\.md|[^/]+\.instructions\.md|CLAUDE\.md|GEMINI\.md|copilot-instructions\.md)$}i
        || $p =~ m{(?:^|/)\.cursor/rules/}i;
}
sub meaningful {
    my ($s) = @_;
    $s =~ s/^\s+|\s+$//g;
    return 0 if !$s || $s =~ /^(?:#|<!--|-->)/;
    $s =~ s/[`*_#>\[\]()-]//g;
    return length($s) >= 12;
}
sub diff_for {
    my ($path) = @_;
    if (defined $head) { return git('diff', '--no-ext-diff', '--unified=0', "$base...$head", '--', $path); }
    if (defined $base) { return git('diff', '--no-ext-diff', '--unified=0', $base, '--', $path); }
    my $d = git('diff', '--no-ext-diff', '--unified=0', 'HEAD', '--', $path);
    $d .= git('diff', '--cached', '--no-ext-diff', '--unified=0', '--', $path);
    return $d;
}

my %changed;
if ($worktree || !defined($base)) {
    $changed{$_} = 1 for split_nul(git('diff', '--name-only', '-z', 'HEAD'));
    $changed{$_} = 1 for split_nul(git('diff', '--cached', '--name-only', '-z'));
    $changed{$_} = 1 for split_nul(git('ls-files', '--others', '--exclude-standard', '-z'));
} elsif (defined $head) {
    $changed{$_} = 1 for split_nul(git('diff', '--name-only', '-z', "$base...$head"));
} else {
    $changed{$_} = 1 for split_nul(git('diff', '--name-only', '-z', $base));
}

if (!%changed) { print "Agent maintenance check: no changed files found.\n"; exit 0; }
my @docs = sort grep { is_instruction($_) && -f "$ROOT/$_" } keys %changed;
my @projects = sort grep { !is_instruction($_) } keys %changed;
if (@projects && !@docs) {
    print STDERR "Agent maintenance check FAILED: project changes require an AGENTS.md, agent, or SKILL.md update.\n";
    exit 1;
}
my $substantive = 0;
for my $p (@docs) {
    my $d = diff_for($p);
    my @lines = grep { /^[+-]/ && !/^(?:\+\+\+|---)/ } split /\n/, $d;
    if (!@lines && !defined($head) && !defined($base)) {
        my $tracked = eval { git('ls-files', '--error-unmatch', '--', $p); 1 };
        if (!$tracked) {
            open my $fh, '<:encoding(UTF-8)', "$ROOT/$p";
            my @content = <$fh>; close $fh if $fh;
            @lines = map { "+$_" } @content;
        }
    }
    $substantive = 1 if grep { my $x = substr($_, 1); meaningful($x) } @lines;
}
if (@projects && !$substantive) {
    print STDERR "Agent maintenance check FAILED: instruction changes need substantive guidance.\n";
    exit 1;
}

my @instruction_files;
find({ no_chdir => 1, wanted => sub {
    return if $File::Find::name =~ m{(?:^|/)\.git(?:/|$)};
    return unless -f $File::Find::name;
    my $rel = File::Spec->abs2rel($File::Find::name, $ROOT);
    push @instruction_files, $File::Find::name if is_instruction($rel);
}}, $ROOT);
my @errors;
for my $file (@instruction_files) {
    my $rel = File::Spec->abs2rel($file, $ROOT);
    open my $fh, '<:encoding(UTF-8)', $file or do { push @errors, "$rel: cannot read"; next; };
    local $/; my $text = <$fh> // ''; close $fh;
    if ($rel =~ m{(?:^|/)SKILL\.md$}i) {
        push @errors, "$rel: missing YAML frontmatter" unless $text =~ /^---\n.*?\n---\n/s;
        push @errors, "$rel: frontmatter missing name" unless $text =~ /^name:\s*\S/m;
        push @errors, "$rel: frontmatter missing description" unless $text =~ /^description:\s*\S/m;
        push @errors, "$rel: missing Maintenance & Continuous Learning" unless $text =~ /^## Maintenance & Continuous Learning\s*$/m;
    }
    if ($rel =~ /\.agent\.md$/i) {
        push @errors, "$rel: missing Post-Change Knowledge Synchronization" unless $text =~ /^## Post-Change Knowledge Synchronization\s*$/m;
    }
    if ($rel =~ /(?:^|\/)AGENTS\.md$/i) {
        push @errors, "$rel: missing Continuous Agent & Skills Maintenance" unless $text =~ /^## Continuous Agent & Skills Maintenance\s*$/m;
    }
    while ($text =~ /(?<!!)\[[^\]]*\]\(([^)]+)\)/g) {
        my $target = $1; $target =~ s/^\s+|\s+$//g; ($target) = split /\s+/, $target;
        next if !$target || $target =~ m{^(?:[a-z][a-z0-9+.-]*:|//|#)}i;
        $target =~ s/[?#].*$//;
        next unless length $target;
        my $dest = File::Spec->canonpath(File::Spec->catfile(dirname($file), $target));
        push @errors, "$rel: local link escapes repository: $target" unless index(File::Spec->rel2abs($dest), "$ROOT/") == 0 || File::Spec->rel2abs($dest) eq $ROOT;
        push @errors, "$rel: broken local Markdown link: $target" unless -e $dest;
    }
}
if (@errors) { print STDERR "Agent maintenance check FAILED:\n", map { "- $_\n" } @errors; exit 1; }
print "Agent maintenance check PASSED (structural checks only).\n";
print "Review semantic relevance of the instruction update manually.\n";
exit 0;
