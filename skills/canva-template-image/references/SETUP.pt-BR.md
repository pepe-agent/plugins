# Configurando a skill do Canva

Você faz isso uma vez só, em uns 15 minutos. As telas do Canva mudam de vez em quando, então use estes passos como um mapa, não como cliques exatos.

## O que você precisa

- Uma conta Canva **Pro, Teams ou Enterprise**. Preencher modelos de marca pela API não existe no plano gratuito, e o Canva pode criar limites de uso.
- Um **modelo de marca** (brand template) com campos que a API consiga preencher (veja a próxima seção).
- Um lugar para rodar o Pepe onde existam `bash`, `curl` e `jq`.

## 1. Crie a integração

1. Abra https://www.canva.com/developers/ e entre com a conta do Canva que é dona dos modelos.
2. Crie uma integração (privada, só para uso seu). Dê um nome, como "Pepe".
3. Em **Scopes** (escopos), ative exatamente estes:
   - `design:content:read`
   - `design:content:write`
   - `brandtemplate:meta:read`
   - `brandtemplate:content:read`
   - `asset:read`
   - `asset:write`
4. Em **Authentication**, cadastre uma **URL de redirecionamento**. Qualquer endereço que seja seu serve, porque você só vai copiar o código da barra de endereço. Por exemplo `http://127.0.0.1:3000/callback` (a página vai dar erro ao abrir, e tudo bem).
5. Copie o **client id** e gere o **client secret**. O Canva mostra o secret uma única vez.

## 2. Prepare o modelo

Abra o modelo no Canva, selecione um elemento (uma caixa de texto ou uma imagem) e, nas opções, escolha conectá-lo a dados (o Canva chama de campos de dados). Dê a cada um um nome curto, sem espaços, como `titulo`, `subtitulo`, `fundo`. Depois publique o design como **modelo de marca**. A API só preenche os elementos marcados assim. O comando `canva.sh fields ID_DO_MODELO` mostra os nomes que ela enxerga.

## 3. Entregue o client id e o secret ao Pepe

Coloque-os no ambiente do servidor do Pepe, como variáveis:

```
CANVA_CLIENT_ID=...
CANVA_CLIENT_SECRET=...
CANVA_REDIRECT_URI=http://127.0.0.1:3000/callback
```

O endereço de redirecionamento precisa ser exatamente o que você cadastrou. Nas configurações do Pepe, adicione os **nomes** das variáveis (nunca os valores) em `secrets.expose_env`, para que a ferramenta `bash` do agente consiga enxergá-las. Mantenha os valores fora de conversas e anotações.

Os tokens ficam em `~/.pepe-canva/` (modo 600). Use `CANVA_STATE_DIR` para mudar o lugar. Trate essa pasta como qualquer outro segredo: ninguém mais deve ler.

## 4. Autorize uma vez

1. Peça ao agente para entrar no Canva, ou rode você mesmo `scripts/canva.sh auth-url`.
2. Abra o link, escolha a conta do Canva e permita o acesso.
3. O navegador vai para o seu endereço de redirecionamento e mostra uma página de erro. Copie o endereço completo da barra (ele tem `code=...`).
4. Passe para o agente, ou rode `scripts/canva.sh auth-code "O-ENDERECO"`.
5. `scripts/canva.sh status` deve responder "authorized".

Os refresh tokens do Canva só valem uma vez. O script grava o novo a cada renovação, então continue usando a mesma pasta de estado. Se ela se perder, repita esta seção.

## Aprovações

A ferramenta `bash` do Pepe pede aprovação a cada chamada, a não ser que o operador libere este script antes. Se você confia nele, libere o comando exato `bash skills/canva-template-image/scripts/canva.sh` (ajuste o caminho para onde a skill foi instalada) e o agente deixa de pedir a cada passo.

## Testando

```
scripts/canva.sh templates
scripts/canva.sh fields ID_DO_MODELO
scripts/canva.sh make ID_DO_MODELO --text titulo="Teste" --out teste.png
```

Cada design criado assim fica na sua conta do Canva; apague os de teste por lá.
