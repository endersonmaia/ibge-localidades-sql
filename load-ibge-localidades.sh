#!/usr/bin/env bash
# MIT License

# Copyright (c) 2020 Enderson Tadeu Salgueiro Maia

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -eo pipefail
[[ $TRACE ]] && set -x

# https://servicodados.ibge.gov.br/api/docs/localidades?versao=1

get_localidades() {
    echo "Baixando Municipios do IBGE..."
    curl -sSL https://servicodados.ibge.gov.br/api/v1/localidades/municipios > "$MUNICIPIOS_JSON_TMP"

    echo "Baixando Subdistritos do IBGE..."
    curl -sSL https://servicodados.ibge.gov.br/api/v1/localidades/subdistritos > "$SUBDISTRITOS_JSON_TMP"
}

load_localidades() {
    echo "Ingerindo dados para tratamento..."

    jq -cr '[.[] | {
        regiao_id: .microrregiao.mesorregiao.UF.regiao.id, regiao_sigla: .microrregiao.mesorregiao.UF.regiao.sigla, regiao_nome: .microrregiao.mesorregiao.UF.regiao.nome,
        uf_id: .microrregiao.mesorregiao.UF.id, uf_sigla: .microrregiao.mesorregiao.UF.sigla, uf_nome: .microrregiao.mesorregiao.UF.nome,
        mesorregiao_id: .microrregiao.mesorregiao.id, mesorregiao_nome: .microrregiao.mesorregiao.nome,
        microrregiao_id: .microrregiao.id, microrregiao_nome: .microrregiao.nome,
        municipio_id: .id, municipio_nome: .nome
        } ] | (map(keys) | add | unique) as $cols | map(. as $row | $cols | map($row[.])) as $rows | $cols, $rows[] | @csv' "$MUNICIPIOS_JSON_TMP" \
        | sqlite3 -csv "$DB_FILE" ".import /dev/stdin _municipios"


    jq -cr '[.[] | {
        distrito_id: .distrito.id, distrito_nome: .distrito.nome,
        subdistrito_id: .id, subdistrito_nome: .nome,
        municipio_id: .distrito.municipio.id,
        microrregiao_id: .distrito.municipio.microrregiao.id,
        mesorregiao_id: .distrito.municipio.microrregiao.mesorregiao.id,
        uf_id: .distrito.municipio.microrregiao.mesorregiao.uf.id,
        regiao_id: .distrito.municipio.microrregiao.mesorregiao.uf.regiao.id
        } ] | (map(keys) | add | unique) as $cols | map(. as $row | $cols | map($row[.])) as $rows | $cols, $rows[] | @csv' "$SUBDISTRITOS_JSON_TMP" \
        | sqlite3 -csv "$DB_FILE" ".import /dev/stdin _subdistritos"
}

load_regioes() {
    echo "Criando tabela regioes..."

    cat <<EOF | sqlite3 "$DB_FILE"
    DROP TABLE IF EXISTS regioes;
    CREATE TABLE IF NOT EXISTS regioes (
        id      INT PRIMARY KEY,
        sigla   CHAR(2),
        nome    VARCHAR(12)
    );
    INSERT INTO regioes (id, sigla, nome)
    SELECT DISTINCT regiao_id, regiao_sigla, regiao_nome
    FROM _municipios;
EOF
}

load_ufs() {
    echo "Criando tabela ufs..."

    cat <<EOF | sqlite3 "$DB_FILE"
    DROP TABLE IF EXISTS ufs;
    CREATE TABLE IF NOT EXISTS ufs (
        id          INT PRIMARY KEY,
        sigla       CHAR(2) NOT NULL,
        nome        TEXT NOT NULL,
        regiao_id   INT NOT NULL,
        FOREIGN KEY(regiao_id) REFERENCES regioes(id)
    );
    CREATE INDEX ufs_regiao_id_index ON ufs(regiao_id);
    INSERT INTO ufs (id, sigla, nome, regiao_id)
    SELECT DISTINCT uf_id, uf_sigla, uf_nome, regiao_id
    FROM _municipios;
EOF
}

load_mesorregioes() {
    echo "Criando tabela mesorregioes..."

    cat <<EOF | sqlite3 "$DB_FILE"
    DROP TABLE IF EXISTS mesorregioes;
    CREATE TABLE IF NOT EXISTS mesorregioes (
        id          INT PRIMARY KEY,
        nome        TEXT NOT NULL,
        uf_id       INT NOT NULL,
        regiao_id   INT NOT NULL,
        FOREIGN KEY (uf_id) REFERENCES ufs (id),
        FOREIGN KEY (regiao_id) REFERENCES regioes (id)
    );
    CREATE INDEX mesorrefioes_uf_id_index ON mesorregioes(uf_id);
    CREATE INDEX mesorrefioes_regiao_id_index ON mesorregioes(regiao_id);
    INSERT INTO mesorregioes (id, nome, uf_id, regiao_id)
    SELECT DISTINCT mesorregiao_id, mesorregiao_nome, uf_id, regiao_id
    FROM _municipios
EOF
}

load_microrregioes() {
    echo "Criando tabela microrregioes..."

    cat <<EOF | sqlite3 "$DB_FILE"
    DROP TABLE IF EXISTS microrregioes;
    CREATE TABLE IF NOT EXISTS microrregioes (
        id              INT PRIMARY KEY,
        nome            TEXT NOT NULL,
        mesorregiao_id  INT NOT NULL,
        uf_id           INT NOT NULL,
        regiao_id       INT NOT NULL,
        FOREIGN KEY (mesorregiao_id) REFERENCES mesorregioes (id),
        FOREIGN KEY (uf_id) REFERENCES ufs (id),
        FOREIGN KEY (regiao_id) REFERENCES regioes (id)
    );
    CREATE INDEX microrregioes_mesorregiao_id_index ON microrregioes(mesorregiao_id);
    CREATE INDEX microrregioes_uf_id_index ON microrregioes(uf_id);
    CREATE INDEX microrregioes_regiao_id_index ON microrregioes(regiao_id);
    INSERT INTO microrregioes (id, nome, mesorregiao_id, uf_id, regiao_id)
    SELECT DISTINCT microrregiao_id, microrregiao_nome, mesorregiao_id, uf_id, regiao_id
    FROM _municipios;
EOF
}

load_municipios() {
    echo "Criando tabela municipios..."

    cat <<EOF | sqlite3 "$DB_FILE"
    DROP TABLE IF EXISTS municipios;
    CREATE TABLE IF NOT EXISTS municipios (
        id              INT PRIMARY KEY,
        nome            TEXT NOT NULL,
        microrregiao_id INT NOT NULL,
        mesorregiao_id  INT NOT NULL,
        uf_id           INT NOT NULL,
        regiao_id       INT NOT NULL,
        FOREIGN KEY (microrregiao_id) REFERENCES microrregioes (id),
        FOREIGN KEY (mesorregiao_id) REFERENCES mesorregioes (id),
        FOREIGN KEY (uf_id) REFERENCES ufs (id),
        FOREIGN KEY (regiao_id) REFERENCES regioes (id)
    );
    CREATE INDEX municipios_microrregiao_id_index ON municipios(microrregiao_id);
    CREATE INDEX municipios_mesorregiao_id_index ON municipios(mesorregiao_id);
    CREATE INDEX municipios_uf_id_index ON municipios(uf_id);
    CREATE INDEX municipios_regiao_id_index ON municipios(regiao_id);
    INSERT INTO municipios (id, nome, microrregiao_id, mesorregiao_id, uf_id, regiao_id)
    SELECT DISTINCT municipio_id, municipio_nome, microrregiao_id, mesorregiao_id, uf_id, regiao_id
    FROM _municipios;
EOF
}

load_distritos() {
    echo "Criando tabela distritos..."

    cat <<EOF | sqlite3 "$DB_FILE"
    DROP TABLE IF EXISTS distritos;
    CREATE TABLE IF NOT EXISTS distritos (
        id              INT PRIMARY KEY,
        nome            TEXT NOT NULL,
        municipio_id    INT NOT NULL,
        microrregiao_id INT NOT NULL,
        mesorregiao_id  INT NOT NULL,
        uf_id           INT NOT NULL,
        regiao_id       INT NOT NULL,
        FOREIGN KEY (municipio_id) REFERENCES municipios (id),
        FOREIGN KEY (microrregiao_id) REFERENCES microrregioes (id),
        FOREIGN KEY (mesorregiao_id) REFERENCES mesorregioes (id),
        FOREIGN KEY (uf_id) REFERENCES ufs (id),
        FOREIGN KEY (regiao_id) REFERENCES regioes (id)
    );
    CREATE INDEX distritos_municipio_id_index ON distritos(municipio_id);
    CREATE INDEX distritos_microrregiao_id_index ON distritos(microrregiao_id);
    CREATE INDEX distritos_mesorregiao_id_index ON distritos(mesorregiao_id);
    CREATE INDEX distritos_uf_id_index ON distritos(uf_id);
    CREATE INDEX distritos_regiao_id_index ON distritos(regiao_id);
    INSERT INTO distritos (id, nome, municipio_id, microrregiao_id, mesorregiao_id, uf_id, regiao_id)
    SELECT DISTINCT distrito_id, distrito_nome, municipio_id, microrregiao_id, mesorregiao_id, uf_id, regiao_id
    FROM _subdistritos;
EOF
}

load_subdistritos() {
    echo "Criando tabela subdistritos..."

    cat <<EOF | sqlite3 "$DB_FILE"
    DROP TABLE IF EXISTS subdistritos;
    CREATE TABLE IF NOT EXISTS subdistritos (
        id              INT PRIMARY KEY,
        nome            TEXT NOT NULL,
        distrito_id     INT NOT NULL,
        municipio_id    INT NOT NULL,
        microrregiao_id INT NOT NULL,
        mesorregiao_id  INT NOT NULL,
        uf_id           INT NOT NULL,
        regiao_id       INT NOT NULL,
        FOREIGN KEY (distrito_id) REFERENCES distritos (id),
        FOREIGN KEY (microrregiao_id) REFERENCES microrregioes (id),
        FOREIGN KEY (mesorregiao_id) REFERENCES mesorregioes (id),
        FOREIGN KEY (uf_id) REFERENCES ufs (id),
        FOREIGN KEY (regiao_id) REFERENCES regioes (id)
    );
    CREATE INDEX subdistritos_distrito_id_index ON subdistritos(distrito_id);
    CREATE INDEX subdistritos_municipio_id_index ON subdistritos(municipio_id);
    CREATE INDEX subdistritos_microrregiao_id_index ON subdistritos(microrregiao_id);
    CREATE INDEX subdistritos_mesorregiao_id_index ON subdistritos(mesorregiao_id);
    CREATE INDEX subdistritos_uf_id_index ON subdistritos(uf_id);
    CREATE INDEX subdistritos_regiao_id_index ON subdistritos(regiao_id);
    INSERT INTO subdistritos (id, nome, distrito_id, municipio_id, microrregiao_id, mesorregiao_id, uf_id, regiao_id)
    SELECT DISTINCT  subdistrito_id, subdistrito_nome, distrito_id, municipio_id, microrregiao_id, mesorregiao_id, uf_id, regiao_id
    FROM _subdistritos;
EOF
}

clean_db(){
    sqlite3 "$DB_FILE" "DROP TABLE _municipios;"
    sqlite3 "$DB_FILE" "DROP TABLE _subdistritos;"
    sqlite3 "$DB_FILE" "VACUUM;"
}

main() {
    trap 'rm -f "$MUNICIPIOS_JSON_TMP"' EXIT
    MUNICIPIOS_JSON_TMP=$(mktemp) || exit 1

    trap 'rm -f "$SUBDISTRITOS_JSON_TMP"' EXIT
    SUBDISTRITOS_JSON_TMP=$(mktemp) || exit 1

    DB_FILE="ibge-localidades.db"

    get_localidades
    load_localidades
    load_regioes
    load_ufs
    load_mesorregioes
    load_microrregioes
    load_municipios
    load_distritos
    load_subdistritos
    clean_db
}

main "$@"