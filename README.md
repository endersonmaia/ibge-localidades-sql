# IBGE Localidades

Este projeto utiliza a API do IBGE para gerar uma base de dados com o Cadastro Brasileiro de  Localidades.

- [IBGE Localidades](#ibge-localidades)
  - [Carregando banco de dados](#carregando-banco-de-dados)
  - [Tabelas](#tabelas)
    - [Regiões](#regiões)
    - [UFs](#ufs)
    - [Mesorregiões](#mesorregiões)
    - [Microrregiões](#microrregiões)
    - [Municípios](#municípios)
    - [Distritos](#distritos)
    - [Subdistritos](#subdistritos)
  - [Licença](#licença)

## Carregando banco de dados

Você precisará dos programas `curl`, `sqlite` e `jq`.

Baixe este repositório, e execute o script `./load-ibge-localidades.sh`.

Segue uma consulta de teste :

```shell
$> cat<<EOF | sqlite3 -csv ibge-localidades.db
    SELECT regiao.sigla, regiao.nome, uf.sigla, uf.nome , count(*) AS qtd_municipios
    FROM municipios    AS m
    JOIN ufs           AS uf       ON (m.uf_id = uf.id)
    JOIN regioes       AS regiao   ON (uf.regiao_id = regiao.id)
    GROUP BY regiao.sigla, regiao.nome, uf.sigla, uf.nome;
EOF
CO,Centro-Oeste,DF,"Distrito Federal",1
CO,Centro-Oeste,GO,"Goiás",246
CO,Centro-Oeste,MS,"Mato Grosso do Sul",79
CO,Centro-Oeste,MT,"Mato Grosso",141
N,Norte,AC,Acre,22
N,Norte,AM,Amazonas,62
N,Norte,AP,"Amapá",16
N,Norte,PA,"Pará",144
N,Norte,RO,"Rondônia",52
N,Norte,RR,Roraima,15
N,Norte,TO,Tocantins,139
NE,Nordeste,AL,Alagoas,102
NE,Nordeste,BA,Bahia,417
NE,Nordeste,CE,"Ceará",184
NE,Nordeste,MA,"Maranhão",217
NE,Nordeste,PB,"Paraíba",223
NE,Nordeste,PE,Pernambuco,185
NE,Nordeste,PI,"Piauí",224
NE,Nordeste,RN,"Rio Grande do Norte",167
NE,Nordeste,SE,Sergipe,75
S,Sul,PR,"Paraná",399
S,Sul,RS,"Rio Grande do Sul",497
S,Sul,SC,"Santa Catarina",295
SE,Sudeste,ES,"Espírito Santo",78
SE,Sudeste,MG,"Minas Gerais",853
SE,Sudeste,RJ,"Rio de Janeiro",92
SE,Sudeste,SP,"São Paulo",645
```

## Tabelas

A hierarquia do CNAE é Região > UF > Mesorregião > Microrregião > Município -> Distrito -> Subdistrito.

Ex.:

```
Cadastro    Código      Sigla   Nome
Região      2           NE      Nordeste
UF          27          AL      Alagoas
Mesorregião 2703                Leste Alagoano
Microregião 27011               Maceió
Município   2704302             Maceió
Distrito    270430205           Maceió
Subdistrito 27043020506         Primeira Região
```

### Regiões

- `regioes`

```sql
campo       tipo
----        ----
id          INT
sigla       CHAR(2)
nome        TEXT
```

### UFs

- `ufs`

```sql
campo       tipo
-----       ----
id          INT
sigla       CHAR(2)
nome        TEXT
regiao_id   INT
```

### Mesorregiões

- `mesorregioes`

```sql
campo       tipo
----        ----
id          INT
nome        TEXT
uf_id       INT
regiao_id   INT
```

### Microrregiões

- `microrregioes`

```sql
campo           tipo
----            ----
id              INT
nome            TEXT
mesorregiao_id  INT
uf_id           INT
regiao_id       INT
```

### Municípios

- `municipios`

```sql
campo           tipo
----            ----
id              INT
nome            TEXT
microrregiao_id INT
mesorregiao_id  INT
uf_id           INT
regiao_id       INT
```

### Distritos

- `distritos`

```sql
campo           tipo
----            ----
id              INT
nome            TEXT
municipio_id    INT
microrregiao_id INT
mesorregiao_id  INT
uf_id           INT
regiao_id       INT
```

### Subdistritos

- `subdistritos`

```sql
campo           tipo
----            ----
id              INT
nome            TEXT
distrito_id     INT
municipio_id    INT
microrregiao_id INT
mesorregiao_id  INT
uf_id           INT
regiao_id       INT
```

## Licença

O código fonte deste projeto é [MIT License](LICENSE), Copyright (c) 2020 Enderson Tadeu Salgueiro Maia.

Os dados são obtivos através da [API do IBGE](https://servicodados.ibge.gov.br/api/docs/localidades?versao=1).