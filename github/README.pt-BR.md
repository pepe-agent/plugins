# GitHub

Buscar, ler, abrir e comentar issues e pull requests do GitHub, e ler os arquivos de um repositório, a partir de um agente do Pepe.

```bash
pepe plugin install @jhonathas/github
```

Funciona com github.com e com o GitHub Enterprise Server.

## Ferramentas

| Ferramenta | O que faz | Altera o GitHub? |
|---|---|---|
| `github_search` | Busca issues e pull requests (sintaxe de busca do GitHub: `repo:`, `is:open`, `is:pr`, `label:`...) | não |
| `github_get_issue` | Lê uma issue ou pull request: quem abriu, estado, etiquetas, texto, últimos comentários e, num pull request, as branches e se foi mesclado | não |
| `github_get_file` | Lê um arquivo de texto de um repositório, ou lista uma pasta, numa branch, tag ou commit | não |
| `github_create_issue` | Abre uma issue e devolve o link | sim |
| `github_comment` | Comenta numa issue ou pull request | sim |

## Configurar (uns 5 minutos)

1. **Crie um token de acesso.** Use um token *fine-grained* (granular), que pode ser limitado aos repositórios e permissões que você escolher. Abra <https://github.com/settings/personal-access-tokens>, escolha **Generate new token** e:
   - dê um nome e uma validade (90 dias é um bom começo);
   - **Resource owner**: você, ou a sua organização (a organização precisa liberar tokens fine-grained antes);
   - **Repository access**: **Only select repositories**, e escolha só os que o agente precisa;
   - **Repository permissions**: **Contents: Read-only**, **Issues: Read-only** para ler (ou **Read and write** se o agente deve abrir issues e comentar), e **Pull requests: Read-only** (ou **Read and write** se deve comentar em pull requests). O Metadata é adicionado sozinho. A página do GitHub mostra os nomes exatos, que podem mudar.

   Copie o token; ele só aparece uma vez.
2. **Preencha o plugin.** No dashboard do Pepe abra **Plugins**, ache o **github** e escolha **Configurar**:

   | Campo | O que colocar |
   |---|---|
   | Access token | O token, escrito como `${GITHUB_TOKEN}`, com o valor real no ambiente do servidor do Pepe, para ele nunca ficar no arquivo de configuração |
   | Default repository | Opcional. Como `acme/app`. Vale quando uma chamada não diz o repositório |
   | Repositories the agent may change | Necessário para abrir issues ou comentar. Como `acme/app, acme/docs` ou `acme/*`, ou `*` para qualquer um. Vazio significa só leitura. Veja *Mantenha seguro* |
   | API address | Só para GitHub Enterprise Server, como `https://git.example.com/api/v3`. Vazio para github.com |

   As mesmas configurações podem vir do ambiente: `GITHUB_TOKEN`, `GITHUB_REPO`, `GITHUB_ALLOWED_REPOS`, `GITHUB_API_URL`.
3. **Dê as ferramentas a um agente.** Ele só tem as que você listar:

   ```bash
   pepe agent tools meu-agente --add github_search,github_get_issue,github_get_file,github_create_issue,github_comment
   ```
4. **Teste.** Peça ao agente: *"liste as issues abertas com a etiqueta bug em acme/app"*, depois *"leia a issue 7"*, depois *"mostre o lib/app.ex"*. Para testar a escrita, liste antes um repositório em *Repositories the agent may change*.

Se algo estiver errado, a ferramenta diz o quê: o GitHub não aceitou o token (confira se está válido), o repositório ou a issue não foi encontrado (um repositório privado que o token não enxerga aparece igual), o token não tem permissão para isso (falta uma permissão), ou o GitHub está limitando o uso do token.

## Mantenha seguro

- **Toda ferramenta pergunta antes de rodar**, a não ser que você a liste no `auto_approve` do agente. Uma divisão sensata é pré-aprovar as três que só leem e deixar as duas que escrevem perguntando.
- **Escrever fica desligado até você dizer onde.** Com *Repositories the agent may change* vazio, o plugin só lê: abrir issues e comentar são recusados antes de qualquer chamada. Liste os repositórios (`acme/app`, ou `acme/*` para todos de um dono) para permitir ali, ou `*` para qualquer um. Ler nunca é limitado por isso, só pelo que o token enxerga.
- **Dê ao token só o que o agente precisa.** O token é o limite de verdade: um token só de leitura não escreve nem que uma configuração esteja errada.
- **O que volta do GitHub foi escrito por quem abriu a issue ou enviou o arquivo**, então chega ao modelo marcado como texto citado, nunca como instrução. Cuidado ao dar muitas ferramentas a um agente que lê issues de fora.

## Observações

- Arquivos acima de 500 KB não são lidos, e um texto é cortado em 20.000 caracteres (a ferramenta avisa). Arquivos que não são texto são informados, não mostrados.
- Os últimos comentários vêm da última página da conversa (até 100 comentários).
- A instalação mostra um aviso `caution` da varredura do Pepe: o plugin lê variáveis de ambiente (para o token), usa a rede e decodifica o base64 que o GitHub devolve para um arquivo. É para isso que ele serve.
- A proteção extra para o texto que vem do GitHub (a execução deixa de honrar o `auto_approve` depois de ler uma issue ou um arquivo) exige um Pepe que conheça o `outside_content?/0`, da versão seguinte à 0.20. Num Pepe mais antigo o plugin funciona e ainda marca o texto como citado, mas as ferramentas pré-aprovadas continuam aprovadas, então não pré-aprove nada arriscado para um agente que lê issues de fora.

---

**In English:** [README.md](https://github.com/pepe-agent/plugins/blob/main/github/README.md)
