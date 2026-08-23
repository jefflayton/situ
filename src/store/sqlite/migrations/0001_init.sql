create table projects (
    id blob primary key not null check (length(id) = 16),
    name text not null,
    created_ts integer not null,
    updated_ts integer not null
) strict;

create table workspaces (
    id blob primary key not null check (length(id) = 16),
    name text not null,
    project_id blob not null references projects (id) on delete cascade,
    created_ts integer not null,
    updated_ts integer not null,

    unique (id, project_id),
    unique (project_id, name)
) strict;

create table notes (
    id blob primary key not null check (length(id) = 16),
    path text not null, -- file path, relative to workspace dir
    project_id blob not null references projects (id) on delete cascade,
    workspace_id blob not null,

    title text,

    modification_ts integer,
    size integer, -- file size
    hash text, -- file hash

    version_vector text not null,
    updated_hlc integer not null, -- Hybrid Logical Clock

    created_ts integer not null,
    deleted_ts integer,

    foreign key (workspace_id, project_id) references workspaces (
        id, project_id
    )
) strict;

create unique index notes_workspace_filepath
on notes (workspace_id, path);

create table op_log (
    id blob primary key not null check (length(id) = 16),
    entity_id blob not null,
    entity_type text not null,
    replica_id blob not null,

    field text not null,
    payload text not null, -- JSON representing what changed

    updated_hlc integer not null,
    version_vector text not null
);

create index entity_ops on op_log (entity_id);
