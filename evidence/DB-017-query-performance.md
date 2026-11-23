- **Identificador de Trabalho (Work ID):** DB-017
- **Título:** Consultas lentas: medir, justificar e comprovar correção
- **Responsável:** Diogo Lopes
- **Revisor:** Isabelly
- **Dependências:** QA-024 (não fornecida; ver seção 8)
- **Autoridade Normativa:** Caderno de Validações de Escopo (AUTH, PI e Extensão), itens 29, 31, 32, 35 e 36
- **Rastreabilidade:** Issue #17 · Migration `V0017__add_public_project_title_index.sql``

---

## 1. Resumo da Entrega

A entrega mede cinco consultas candidatas do fluxo de projetos e inscrições em dois volumes de dados sintéticos, registra planos e tempos antes e depois, e só corrige o que a medição justifica.

Resultado:

- **Uma correção justificada:** índice parcial `idx_project_public_title` em `academic_pi.project (title) WHERE is_public AND status = 'published'`, para a listagem pública paginada (consulta Q1 com `LIMIT 20`). Na revalidação pareada com 30 mil projetos, a mediana caiu de 2,004 ms (`Seq Scan`) para 0,056 ms (`Index Scan`), cerca de 35,8 vezes.
- **Uma correção testada e descartada:** índice `(closes_at, opens_at)` em `enrollment_period` para a consulta Q5. O ganho ficou dentro do ruído de medição e o índice foi removido.
- **Três consultas sem alteração justificada:** Q2, Q3 e Q4 já usam índices existentes e respondem em menos de 1 ms mesmo com 750 mil participações.

Limitação principal: as consultas são **candidatas, derivadas do Caderno**, e não foram observadas na QA-024. A medição é local, em Docker, e **não representa desempenho de produção**.

---

## 2. Ambiente

| Item | Valor |
| :--- | :--- |
| PostgreSQL | 16.15 (imagem Alpine), 64 bits |
| Recursos do Docker | 12 CPUs, 16.673.153.024 bytes de memória (cerca de 15,5 GiB) |
| Execução | Local, Docker Desktop, Windows; cache quente (as leituras vêm de `shared hit`) |
| Base | Branch `DB-017-consultas-lentas-medicao`, criada a partir da `develop` no commit `ffc3a11` (DB-016, #39) |
| Migrations aplicadas | V0001, V0002, V0003, V0004, V0006, V0007, V0008, V0011 e V0017 |
| Método | Cada consulta executada três vezes com `EXPLAIN (ANALYZE, BUFFERS)`; a tabela usa a mediana. A carga atualizou as estatísticas com `ANALYZE`; a tabela `project` foi analisada novamente após a remoção do índice para a medição sem V0017. |
| Validação | `scripts/validate.sh` e `scripts/validate_upgrade.sh` concluídos com sucesso em banco de validação com migrations e seeds. O upgrade não detectou drift. |

---

## 3. Dados Sintéticos e Volume

Os dados são **suposições nossas** (a QA-024 não informou volume). São determinísticos (sem `random()`), sem dado pessoal (`@synthetic.local`) e gerados por `evidence/DB-017-load.sql`, com variáveis do `psql`.

| Parâmetro | Volume pequeno | Volume de estresse |
| :--- | :--- | :--- |
| Alunos (`n_students`) | 5.000 | 250.000 |
| Projetos (`n_projects`) | 600 | 30.000 |
| Docentes (`n_instr`) | 100 | 1.000 |
| Usuários totais | 5.100 | 251.000 |
| Projetos (com seed) | 604 | 30.004 |
| Docentes por projeto | 903 | 45.003 |
| Períodos de inscrição | 1.203 | 60.003 |
| Participações | 15.005 | 750.005 |

Regras da carga: 60% dos projetos publicados, 25% rascunho, 15% arquivados; 10% marcados como públicos; cada aluno com um PI ativo (20% ainda `requested`), uma Extensão ativa e um PI recusado, respeitando o limite de 1 PI + 1 Extensão (item 32). Tamanho no volume de estresse: `project_participation` 205 MB, `auth.user` 82 MB, `enrollment_period` 8.800 kB, `project` 8.800 kB, `project_instructor` 7.760 kB.

---

## 4. Consultas Candidatas

Script: `evidence/DB-017-queries.sql`. A data de referência é fixa (`2026-11-20 12:00:00-03`), e não `now()`, para repetir a mesma janela no antes e no depois.

| # | Consulta | Caderno | Variante medida |
| :--- | :--- | :--- | :--- |
| **Q1** | Portal público: projetos publicados e marcados como públicos, ordenados por título | 29 e 35 | Completa (3.002 linhas) e paginada (`LIMIT 20`) |
| **Q2** | Participações ativas de um aluno | 31 e 32 | |
| **Q3** | Solicitações pendentes de um projeto (tela de aprovação do docente) | 30 e 31 | |
| **Q4** | Projetos de um docente com período de inscrição aberto na data de referência | 31 e 36 | |
| **Q5** | Projetos publicados com período de inscrição aberto na data de referência | 31 e 36 | |
| **W1** | Custo de escrita: 20 mil projetos inseridos e desfeitos com `ROLLBACK` | | `evidence/DB-017-write-cost.sql` |

---

## 5. Resultados

### 5.1 Volume pequeno (604 projetos, 15.005 participações)

Todas as consultas ficaram entre 0,04 e 0,22 ms nas execuções observadas. As leituras sem índice (`Seq Scan`) ocorreram apenas em tabelas de 8 a 14 páginas, onde ler tudo é mais barato que usar índice. Nenhuma correção se justifica nesse volume.

Uma primeira série foi descartada: o script de leitura continha o W1, e a inserção desfeita com `ROLLBACK` deixou linhas mortas em `project`. A tabela passou de 8 para 749 páginas e o Q5 subiu de 0,2 ms para 1,3 ms só por esse inchaço. O W1 foi movido para um script separado, que termina com `VACUUM (ANALYZE)`.

### 5.2 Volume de estresse, medição inicial sem índices novos

| Consulta | Plano | Tempos (ms) | Mediana (ms) |
| :--- | :--- | :--- | :--- |
| Q1 completa | `Seq Scan` em `project` (3.002 de 30.004 linhas), ordenação | 5,241 / 4,976 / 4,753 | **4,976** |
| Q1 paginada | `Seq Scan` em `project` | 4,450 / 2,514 / 2,537 | **2,537** |
| Q2 | `Index Scan` em `idx_project_participation_student_id` (já existe) | 0,049 / 0,067 / 0,032 | **0,049** |
| Q3 | `Bitmap Index Scan` em `project_participation_project_student_unq` (já existe) | 0,224 / 0,270 / 0,192 | **0,224** |
| Q4 | `Bitmap Index Scan` em `idx_project_instructor_instructor_id` e `Index Scan` em `idx_enrollment_period_project_id` (já existem) | 0,530 / 0,545 / 0,601 | **0,545** |
| Q5 | `Seq Scan` em `enrollment_period` (7.500 de 60.003) e em `project` | 10,829 / 13,781 / 11,535 | **11,535** |

### 5.3 Volume de estresse, medição experimental com dois índices

| Consulta | Plano | Tempos (ms) | Mediana (ms) |
| :--- | :--- | :--- | :--- |
| Q1 completa | `Bitmap Index Scan` em `idx_project_public_title` | 3,944 / 4,091 / 3,931 | **3,944** |
| Q1 paginada | `Index Scan` em `idx_project_public_title` | 0,064 / 0,074 / 0,070 | **0,070** |
| Q2 | igual ao antes | 0,047 / 0,042 / 0,030 | **0,042** |
| Q3 | igual ao antes | 0,335 / 0,209 / 0,188 | **0,209** |
| Q4 | igual ao antes | 0,391 / 0,335 / 0,305 | **0,335** |
| Q5 | `Bitmap Index Scan` em `idx_enrollment_period_closes_at` | 8,757 / 9,419 / 10,333 | **9,419** |

Leitura:

- **Ruído do ambiente:** Q2, Q3 e Q4 não foram afetadas por nenhum índice novo e mesmo assim variaram até 40% (o Q4 caiu de 0,545 para 0,335 ms). Diferenças dessa ordem não provam ganho.
- **Q1 completa:** 4,98 para 3,94 ms, dentro do ruído. Sem `LIMIT`, o índice não se justifica.
- **Q1 paginada:** nesta medição experimental, de 2,537 ms para 0,070 ms. A revalidação pareada está registrada na seção 5.5.
- **Q5:** de 11,5 para 9,4 ms (cerca de 18%), mas a consulta devolve milhares de linhas e continua lendo `project` inteira. O ganho não se distingue do ruído e o índice custa 432 kB.

### 5.4 Medição inicial depois da migration V0017

| Consulta | Plano | Tempos (ms) | Mediana (ms) |
| :--- | :--- | :--- | :--- |
| Q1 paginada | `Index Scan` em `idx_project_public_title` | 0,118 / 0,053 / 0,050 | **0,053** |

### 5.5 Revalidação pareada da Q1 paginada

Com a mesma carga de estresse no mesmo banco, a consulta paginada foi executada três vezes com o índice removido e três vezes com o índice da V0017 presente. Os planos completos estão nos arquivos `evidence/DB-017-queries-antes-v0017.txt` e `evidence/DB-017-queries-apos-v0017.txt`.

| Estado | Plano | Execuções (ms) | Mediana (ms) |
| :--- | :--- | :--- | :--- |
| Sem `idx_project_public_title` | `Seq Scan` e `top-N heapsort` | 2,004 / 1,950 / 2,112 | **2,004** |
| Com `idx_project_public_title` | `Index Scan` | 0,063 / 0,056 / 0,045 | **0,056** |

A mediana caiu de 2,004 ms para 0,056 ms, cerca de **35,8 vezes**. O banco foi mantido com os mesmos dados durante as duas séries; somente o índice foi removido ou restaurado.

---

## 6. Decisão e Trade-offs

| Item | Decisão | Motivo |
| :--- | :--- | :--- |
| `idx_project_public_title` | **Mantido** (migration V0017) | Na revalidação pareada, a Q1 paginada caiu de 2,004 para 0,056 ms; o índice usa somente coluna e predicado públicos |
| `idx_enrollment_period_closes_at` | **Descartado** | Ganho dentro do ruído; 432 kB; a consulta devolve milhares de linhas |
| Q2, Q3, Q4 | **Sem alteração** | Já usam índices existentes e respondem em menos de 1 ms |

**Custo do índice mantido:**

- **Espaço:** 136 kB com 30.004 projetos (o índice só guarda os projetos públicos e publicados, cerca de 10%).
- **Criação:** 19,5 ms com 30 mil projetos. `CREATE INDEX` comum bloqueia escritas na tabela enquanto roda; o tempo cresce com o tamanho da tabela. `CREATE INDEX CONCURRENTLY` não pode ser executado dentro de `BEGIN ... COMMIT`, que é o padrão das migrations do repositório.
- **Escrita (W1, 20 mil projetos inseridos, 10% públicos e publicados), em ms:**

| Situação | Execuções | Mediana |
| :--- | :--- | :--- |
| Sem índice novo (estresse) | 76,310 / 78,026 / 96,636 | 78,026 |
| Com o índice de `project` (6 execuções: 3 nos testes e 3 depois da migration) | 80,496 / 81,478 / 84,438 / 87,890 / 96,252 / 115,764 | 86,164 |

A diferença das medianas é de cerca de 10%, mas as faixas se sobrepõem, e a mesma configuração já variou de 76 a 97 ms. No volume pequeno, sem índice novo, o W1 levou de 98,8 a 109,9 ms. O custo de escrita **não é distinguível do ruído**; a estimativa conservadora é de até 10 a 20% em inserções de projetos.

---

## 7. Auditoria de Índices

Critério: nenhum índice deve cobrir dado privado apenas para acelerar consulta pública.

Foram listados os 35 índices dos schemas `academic_pi`, `assets` e `auth` antes da mudança.

- Antes: **nenhum índice** em `academic_pi.project` além da chave primária e de `project_id_category_unq`. Os índices que tocam dados sensíveis (`cpf` e `email` em `auth.user`, `token_hash` em `auth.user_session`, `content_hash`, `owner_user_id` e `storage_ref` em `assets.project_file`) existem para uso interno (unicidade, login, sessão e arquivos), e nenhum serve à consulta pública. Os arquivos são privados pelo item 53 do Caderno.
- O índice novo usa **uma coluna pública** (`title`) e um **predicado público** (`is_public AND status = 'published'`, itens 29 e 35). Não usa `INCLUDE` e não toca CPF, e-mail, notas, horas ou arquivos.

Observação fora do escopo, sem alteração: existem índices redundantes em `auth` (`idx_user_cpf` com `user_cpf_unq`, `idx_user_email` com `user_email_unq`, `idx_user_identity_provider_subject` com `user_identity_provider_subject_unq`), porque cada índice único já serve de índice de busca.

---

## 8. Limitações e Pontos em Aberto

- **QA-024 não fornecida:** as consultas são candidatas, derivadas dos acessos descritos no Caderno. O critério “cada correção está vinculada a uma consulta observada em QA-024” **não está atendido ao pé da letra**: a correção está vinculada à Q1, que é uma suposição.
- **Forma da consulta pública:** o ganho depende de o portal ordenar por título e paginar. Sem `LIMIT`, o índice não trouxe ganho relevante. Se o portal ordenar por outro campo, o índice não serve.
- **Proporção de projetos públicos:** assumida em 10%. O índice parcial perde vantagem se a maioria dos projetos for pública.
- **Medição local:** Docker Desktop, cache quente, uma máquina. Não declara desempenho de produção.
- **Arquivos (`assets.project_file`):** não medidos. A tabela `assets.file_lifecycle_state` está vazia e é referência de outra issue, então a carga não gerou arquivos.
- **Q5:** a solução adequada para “períodos abertos em uma data” seria um índice de intervalo (`tstzrange` com GiST), que altera esquema e consulta. Fica como sugestão fora desta issue.

---

## 9. Reprodução

Execute os comandos abaixo apenas em uma base local descartável: `docker compose down -v` remove o volume do PostgreSQL.

```bash
docker compose down -v
docker compose up -d --wait
./scripts/migrate.sh
./scripts/seed.sh

docker compose exec -T postgres psql \
  -v ON_ERROR_STOP=1 \
  -v n_students=250000 \
  -v n_projects=30000 \
  -v n_instr=1000 \
  -U plataforma -d plataforma \
  < evidence/DB-017-load.sql
```

Com a V0017 aplicada e o índice presente, capture a série “depois”:

```bash
set -o pipefail
for run in 1 2 3; do
  echo "===== REPETICAO $run - APOS V0017 ====="
  docker compose exec -T postgres psql \
    -v ON_ERROR_STOP=1 \
    -U plataforma -d plataforma \
    < evidence/DB-017-queries.sql
done 2>&1 | tee evidence/DB-017-queries-apos-v0017.txt
```

Remova somente o índice, atualize as estatísticas e capture a série “antes” sem recarregar os dados:

```bash
docker compose exec -T postgres psql \
  -v ON_ERROR_STOP=1 \
  -U plataforma -d plataforma \
  -c "DROP INDEX academic_pi.idx_project_public_title; ANALYZE academic_pi.project;"

set -o pipefail
for run in 1 2 3; do
  echo "===== REPETICAO $run - ANTES V0017 ====="
  docker compose exec -T postgres psql \
    -v ON_ERROR_STOP=1 \
    -U plataforma -d plataforma \
    < evidence/DB-017-queries.sql
done 2>&1 | tee evidence/DB-017-queries-antes-v0017.txt
```

Restaure o índice executando a migration diretamente. Como V0017 já está registrada em `schema_migration`, `scripts/migrate.sh` pode ignorá-la:

```bash
docker compose exec -T postgres psql \
  -v ON_ERROR_STOP=1 \
  -U plataforma -d plataforma \
  < migrations/V0017__add_public_project_title_index.sql
```

O custo de escrita (W1) fica em `evidence/DB-017-write-cost.sql`. Rode-o separadamente, depois das medições de leitura: o `INSERT` com `ROLLBACK` deixa linhas mortas em `project` até o `VACUUM`.

Validações registradas:

- `evidence/DB-017-validate.txt`: validação completa em banco com migrations e seeds, sem a carga de estresse.
- `evidence/DB-017-validate-upgrade.txt`: upgrade incremental, idempotência de migrations e seeds, validação completa e comparação de drift. Resultado: sucesso, sem drift.

A validação de upgrade cria e remove o banco temporário `plataforma_upgrade_test`. A base principal de medição é preservada.

---

## 10. Rastreabilidade

- **Issue:** #17 (Consultas lentas: medir, justificar e comprovar correção)
- **Migration:** `migrations/V0017__add_public_project_title_index.sql`
- **Scripts:** `evidence/DB-017-load.sql`, `evidence/DB-017-queries.sql`, `evidence/DB-017-write-cost.sql`
- **Planos pareados:** `evidence/DB-017-queries-antes-v0017.txt`, `evidence/DB-017-queries-apos-v0017.txt`
- **Validações:** `evidence/DB-017-validate.txt`, `evidence/DB-017-validate-upgrade.txt`
- **Validação do repositório:** `scripts/validate.sh` inclui o índice novo `idx_project_public_title` na lista esperada
- **Branch:** `DB-017-consultas-lentas-medicao`