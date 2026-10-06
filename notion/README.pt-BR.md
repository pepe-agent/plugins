# Notion

Buscar, ler, criar e acrescentar texto em páginas e bancos de dados do Notion a partir de um agente do Pepe.

```bash
pepe plugin install @jhonathas/notion
```

## Ferramentas

| Ferramenta | O que faz | Altera o Notion? |
|---|---|---|
| `notion_search` | Busca páginas e bancos de dados pelo título | não |
| `notion_get_page` | Lê uma página: as propriedades e o conteúdo como texto | não |
| `notion_query_database` | Lista as linhas de um banco de dados com as propriedades, opcionalmente filtradas com um filtro do Notion | não |
| `notion_create_page` | Cria uma página com título e texto, dentro de uma página ou como linha de um banco de dados | sim |
| `notion_append` | Acrescenta texto no fim de uma página | sim |

## Configurar (uns 5 minutos)

O Notion funciona diferente da maioria dos serviços: **uma integração só enxerga as páginas que foram compartilhadas com ela.** É o passo que mais se esquece, então ele vem primeiro.

1. **Crie a integração.** Abra <https://www.notion.so/profile/integrations>, escolha **New integration**, dê um nome (por exemplo, "Pepe"), escolha o workspace e mantenha o tipo **Internal**. Em **Capabilities**, marque **Read content**. Marque **Insert content** e **Update content** só se o agente deve criar páginas e acrescentar texto. Salve.
2. **Copie o token.** Na página da integração, copie o **Internal Integration Secret** (começa com `ntn_` ou `secret_`).
3. **Compartilhe as páginas com ela.** Abra cada página ou banco de dados que o agente deve alcançar, escolha **...** (canto superior direito) → **Connections** → **Add connections**, e selecione a integração. Compartilhar uma página também compartilha tudo que está dentro dela, então muitas vezes basta compartilhar uma página-mãe. Sem esse passo, toda chamada responde "não encontrei".
4. **Preencha o plugin.** No dashboard do Pepe abra **Plugins**, ache o **notion** e escolha **Configurar**:

   | Campo | O que colocar |
   |---|---|
   | Integration token | O token, escrito como `${NOTION_TOKEN}`, com o valor real no ambiente do servidor do Pepe, para ele nunca ficar no arquivo de configuração |
   | Allow writing | `no` (o padrão) significa só leitura. Coloque `yes` para permitir criar páginas e acrescentar texto |

   As mesmas configurações podem vir do ambiente: `NOTION_TOKEN`, `NOTION_WRITES` (`yes`).
5. **Dê as ferramentas a um agente.** Ele só tem as que você listar:

   ```bash
   pepe agent tools meu-agente --add notion_search,notion_get_page,notion_query_database,notion_create_page,notion_append
   ```
6. **Teste.** Peça ao agente: *"busque no Notion o roadmap"*, depois *"leia essa página"*. Também dá para entregar o endereço de uma página: ele entende tanto o endereço quanto o id.

Se algo estiver errado, a ferramenta diz o quê: o Notion não aceitou o token, a página ou o banco de dados não está compartilhado com a integração (a mensagem diz onde compartilhar), a integração não tem uma permissão, ou o Notion está limitando o uso (a mensagem diz quanto esperar).

## Mantenha seguro

- **Toda ferramenta pergunta antes de rodar**, a não ser que você a liste no `auto_approve` do agente. Uma divisão sensata é pré-aprovar as três que só leem e deixar as duas que escrevem perguntando.
- **Escrever fica desligado até você ligar** (*Allow writing*), e mesmo assim só escreve onde a integração foi compartilhada. Compartilhe a integração com o menor conjunto de páginas que o agente precisa: esse é o limite de verdade.
- **O que volta do Notion foi escrito por quem pode editar a página**, então chega ao modelo marcado como texto citado, nunca como instrução. Cuidado ao dar muitas ferramentas a um agente que lê páginas compartilhadas.

## Observações

- A busca olha os títulos, não o texto dentro das páginas.
- Uma página é lida como texto simples: títulos, listas, tarefas, citações, código, tabelas e blocos aninhados (alguns níveis, dentro de um limite de chamadas). Imagens e arquivos aparecem como `[image]` ou `[file]`. Páginas muito longas são cortadas em 20.000 caracteres, e a ferramenta avisa.
- Páginas criadas e texto acrescentado são parágrafos simples (linha em branco faz parágrafo). Formatações como negrito, tabelas e menções não são geradas ao escrever.
- Criar uma linha num banco de dados preenche só o título; as outras propriedades ficam vazias.
- Usa a versão `2022-06-28` da API do Notion.
- A instalação mostra um aviso `caution` da varredura do Pepe: o plugin lê variáveis de ambiente (para o token) e usa a rede. É para isso que ele serve.
- A proteção extra para o texto que vem do Notion (a execução deixa de honrar o `auto_approve` depois de ler uma página) exige um Pepe que conheça o `outside_content?/0`, da versão seguinte à 0.20. Num Pepe mais antigo o plugin funciona e ainda marca o texto como citado, mas as ferramentas pré-aprovadas continuam aprovadas, então não pré-aprove nada arriscado para um agente que lê páginas compartilhadas.

---

**In English:** [README.md](https://github.com/pepe-agent/plugins/blob/main/notion/README.md)
