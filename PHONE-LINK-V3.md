# notfcode Phone Link — protocolo v3

**Estado:** contrato normativo da implementação. O servidor do aplicativo desktop e o cliente móvel devem seguir esta especificação. Em caso de divergência entre o documento e o código, este documento prevalece.

## Por que existe a versão 3

A revisão da versão 2 identificou três riscos: o serviço escutava em `0.0.0.0` e deixava a rota de pareamento permanentemente disponível; os corpos passavam pela rede local em texto puro e as respostas não eram autenticadas; e os segredos dos dispositivos eram armazenados em arquivo sem proteção. A versão 3 protege os dados transmitidos e restringe a janela de pareamento. A proteção do armazenamento é tratada separadamente, exceto onde afeta o protocolo.

## Requisitos de segurança

- O aplicativo móvel não depende de módulos nativos de TLS, certificados individuais nem pinagem de certificados; o Expo Go deve continuar funcionando. A criptografia ocorre na camada da aplicação.
- O código de pareamento mostrado no QR é o único canal externo necessário para estabelecer a confiança inicial.
- Segredos nunca devem ser enviados pela rede.
- **A versão 2 foi removida, não há modo de compatibilidade.** Após a atualização, os dispositivos precisam ser pareados novamente.

Entradas antigas em `devices.json` contêm segredos derivados na versão 2 e não podem ser atualizadas de modo seguro. Ao carregar o arquivo, descarte as entradas antigas e regrave o inventário. Não grave o segredo v2 no chaveiro. A interface deve avisar que é necessário parear o telefone novamente. A rota `/health` anuncia `"api": 3`, e o cliente recusa parear se receber uma versão inferior.

A rota legado v1 do agente Python independente (`agent/notfcode_agent.py`), com segredo estático e texto sem criptografia, permanece no cliente móvel temporariamente e está fora do escopo desta implementação. Enquanto uma ligação v1 estiver ativa, o aplicativo móvel precisa manter um aviso persistente: **“Sem criptografia (agente legado)”**.

## Derivação de chaves

O código `C` contém 16 bytes aleatórios obtidos por um gerador criptográfico, representados como 32 caracteres hexadecimais. Isso não muda em relação à versão 2.

**Todo material de chave é composto por bytes brutos. Nunca use a representação hexadecimal ASCII como chave HMAC.**

O segredo do dispositivo é derivado independentemente nos dois lados e nunca é transmitido:

```text
S = HMAC-SHA256(key = hexdecode(C), msg = "notfcode-device-v3:" + deviceId)  // 32 bytes brutos
```

As chaves para cada finalidade são derivadas com HKDF-SHA256 (RFC 5869), salt de comprimento zero e L = 32:

```text
K_sig      = HKDF(IKM = S,            info = "notfcode/v3/sig")
K_enc      = HKDF(IKM = S,            info = "notfcode/v3/enc")
K_pair_sig = HKDF(IKM = hexdecode(C), info = "notfcode/v3/pair-sig")
K_pair_enc = HKDF(IKM = hexdecode(C), info = "notfcode/v3/pair-enc")
```

Cada chave tem uma finalidade. Não reutilize a mesma chave para assinatura e criptografia.

## Envelope criptografado

Todo corpo que carrega conteúdo, incluindo solicitações e respostas de pareamento, usa este formato:

```text
base64( nonce12 || ciphertext || tag16 )
```

- Algoritmo: AES-256-GCM, com `K_enc` (ou `K_pair_enc` no pareamento).
- `nonce12`: 12 bytes frescos por mensagem, obtidos por gerador criptográfico. A resposta nunca pode reutilizar o nonce da solicitação.
- O corpo é texto Base64 com `content-type: application/notfcode-v3`, porque `fetch` no React Native não lida de forma confiável com corpos binários brutos.

### Requisições sem corpo

`GET /api/v3/snapshot` e `POST /api/v3/refresh` não têm corpo de requisição. O cliente envia a requisição sem corpo e sem `content-type`; não envia envelope vazio nem adiciona corpo a um GET. A assinatura continua usando `sha256hex("")` na fórmula. O servidor não tenta descriptografar um corpo ausente. Respostas são sempre criptografadas, inclusive para solicitações sem corpo.

Um corpo vazio autenticado prova que o cliente realmente não enviou conteúdo, porque o hash é incluído na string assinada. Um intermediário não consegue remover um corpo sem invalidar a autenticação da mensagem.

## Dados autenticados adicionais (AAD)

Os campos ASCII são separados por `|`, sem separador final:

```text
requisição:          v3|req|<ts>|<nonce>|<METHOD>|<path>|<deviceId>
resposta:            v3|res|<ts>|<nonce>|<METHOD>|<path>|<deviceId>|<status>
requisição de par:   v3|pair-req|<ts>|<nonce>|POST|/api/v3/pair|<deviceId>
resposta de parear:  v3|pair-res|<ts>|<nonce>|POST|/api/v3/pair|<deviceId>|<status>
```

Na AAD da resposta, `<ts>` e `<nonce>` são os valores da requisição que produziu aquela resposta. Assim, uma resposta capturada não pode ser repetida ou anexada a outra solicitação. `<path>` não inclui a query string; `<status>` é o código HTTP numérico.

## Cabeçalhos

Os nomes permanecem:

- `x-cn-timestamp`: segundos desde a época Unix, em decimal.
- `x-cn-nonce`: 16 bytes aleatórios em formato hexadecimal, com 32 caracteres.
- `x-cn-device`: ID do dispositivo em texto puro, inclusive no pareamento.
- `x-cn-signature`: assinatura descrita abaixo.

O nonce deve vir de um gerador criptográfico; no telefone, use `expo-crypto` com `getRandomBytesAsync`. O nonce da versão 2 formado por `n-${Date.now()}-${Math.random()}` não é aceitável. O ID do dispositivo é um UUID aleatório sem informação sensível e fica em texto para integrar a AAD. Nome e plataforma do dispositivo permanecem criptografados.

## Assinatura: criptografar e depois autenticar

```text
sig = HMAC-SHA256(K_sig,
  "<ts>.<nonce>.<METHOD>.<uri>.<sha256hex(body-as-sent)>")
```

A assinatura é codificada em hexadecimal e comparada em tempo constante. `body-as-sent` são os bytes do envelope Base64 enviados no corpo; a assinatura cobre o texto cifrado, não o texto original. Não inverta a ordem de criptografia e MAC. `<uri>` é o destino completo da requisição, incluindo query string, conforme o comportamento anterior da versão 2. As requisições de pareamento usam `K_pair_sig`.

As respostas **não** incluem cabeçalho de assinatura separado. AES-GCM e a AAD da resposta já autenticam a mensagem; não adicione um MAC redundante.

## Erros sem autenticação

Alguns erros ocorrem antes que exista chave disponível, como `unknown-device`, `pairing-closed` e `rate-limited`. Esses corpos permanecem JSON em texto puro.

O cliente **não pode alterar estado persistente** após receber um erro não autenticado. Não apague o segredo guardado, não desfaça o pareamento e não limpe a conexão ao receber 401, 403 ou 429; mostre apenas um estado para tentar novamente. Caso contrário, qualquer participante da rede local poderia falsificar um 401 e desparear o telefone.

Erros `clock-skew` incluem `serverTime` e também não são autenticados. Preserve a lógica `learnSkew`, mas rejeite diferenças implícitas maiores que 24 horas. Um valor forjado poderá causar negação de serviço, mas não deverá permitir repetição de solicitações: o timestamp está na assinatura e na AAD, e o servidor aceita nonces apenas uma vez.

## Endpoints

| Rota | Autenticação | Corpo |
|---|---|---|
| `GET /health` | Nenhuma | JSON sem criptografia: `{"ok":true,"app":"notfcode","api":3,"version":"x.y.z"}` |
| `POST /api/v3/pair` | `K_pair_sig` e janela de pareamento aberta | Criptografado com `K_pair_enc` |
| `GET /api/v3/snapshot` | `K_sig` | Criptografado com `K_enc` |
| `POST /api/v3/refresh` | `K_sig` | Criptografado com `K_enc` |

`/health` continua em texto puro porque serve para descoberta, não contém segredo e precisa estar disponível antes de existir uma chave. O conteúdo lógico da solicitação de pareamento é `{"deviceId","name","platform"}` e a resposta lógica é `{"paired":true,"server","version","api":3,"deviceId"}`; ambos ficam dentro do envelope criptografado.

## Janela de pareamento

O endpoint de pareamento só pode ser acessado quando uma pessoa estiver com o QR aberto na tela:

- O código é criado quando a janela de pareamento abre, não no inicializador da tela `PhoneLinkPairing`.
- Com a janela fechada, não há código ativo nem temporizador de rotação.
- `POST /api/v3/pair` responde `403 {"error":"pairing-closed"}` se a janela não estiver aberta.
- A janela fecha após pareamento bem-sucedido, fechamento manual ou cinco minutos.
- O tratamento de códigos aposentados continua ativo e retorna `{"error":"code-expired"}` sem permitir novo pareamento.

## Endereço de escuta

Escute em cada endereço IPv4 privado retornado por `PhoneLinkNetwork.getHosts()` e também em `127.0.0.1`, usando um canal NIO por endereço. A regra é: **o servidor deve escutar exatamente nos endereços que o QR oferece**.

Reabra os canais quando a rede mudar por meio de `NWPathMonitor`. Se não houver endereço privado, não abra socket e mostre `.failed("no private network")`.

Essa regra não torna uma rede Wi-Fi pública confiável: o endereço `en0` ainda pertence à rede do café. Ela impede, porém, a escuta em `awdl0`, `utun*` (VPN), pontes Thunderbolt ou USB e falha de forma fechada quando o Mac possui diretamente um endereço público. O risco em uma rede compartilhada é reduzido sobretudo pela janela de pareamento, não apenas pelo endereço de escuta.

## Repetição e limites de requisição

- O registro de nonces é indexado por `deviceId` em `/api/v3/*` e por IP em `/api/v3/pair`, já que ainda não há identidade estabelecida durante o pareamento.
- A tolerância do timestamp continua sendo ±120 segundos.
- Os nonces são mantidos por 300 segundos.
- Os limites permanecem: 10 requisições por minuto por IP na rota de pareamento e 120 por minuto na API.
- O corpo fica limitado a 64 KiB; esse limite deve ser aplicado ao envelope antes de decodificar Base64.

## Armazenamento no Mac

`PairedDevice` não deve mais possuir o campo `secret`. Metadados como `deviceId`, `name`, `platform`, `pairedAt`, `lastSeenAt` e `lastSeenIP` podem permanecer no arquivo de dispositivos; o segredo derivado é reconstituído conforme o esquema v3 quando necessário e não é persistido em texto claro.
