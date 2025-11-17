import{j as e,r as s}from"./iframe-BXD7fudD.js";import{C as n}from"./Card-Hc4ICV2v.js";import{P as o,S as i,T as c}from"./Button-BWCiYP-u.js";import{I as m}from"./Input-Bm4vLXlM.js";import{S as x}from"./Select-Cqc8kr0O.js";import{P as l,S as t,a as p}from"./Typography-D3LeKxqU.js";import"./preload-helper-JDnY5PGr.js";const Y={title:"Rostoc Design System/Overview",parameters:{layout:"fullscreen",docs:{description:{component:`Rostoc Design System Overview

This overview showcases the complete Rostoc design system based on the Figma design file.

## Design Principles
- **Typography**: Space Grotesk for titles, Instrument Sans for body text
- **Colors**: Coal (#222222) background, Tomato (#e4410a) primary, Cream (#f4f3dd) text
- **Spacing**: Consistent 8px grid system (4px, 8px, 16px, 24px, 32px, 40px)
- **Borders**: Thin (1px), Default (2px), Thick (3.5px)

## Figma Reference
Design source: https://www.figma.com/design/tuTsF90yrx8CSTkyTlKxcz/Rostoc?node-id=315-9650`}}},tags:["autodocs"]},a={render:()=>{const[S,C]=s.useState(""),[T,B]=s.useState(""),[E,A]=s.useState("english"),[D,P]=s.useState("dd/mm/yyyy");return e.jsxs("div",{className:"px-[36px] py-8",children:[e.jsx(l,{title:"Rostoc Design System",subtitle:"A comprehensive example of all components"}),e.jsx(t,{title:"Buttons"}),e.jsxs("div",{className:"flex gap-4 mb-12",children:[e.jsx(o,{onClick:()=>console.log("Primary clicked"),children:"PRIMARY BUTTON"}),e.jsx(i,{onClick:()=>console.log("Secondary clicked"),children:"SECONDARY BUTTON"}),e.jsx(c,{onClick:()=>console.log("Text clicked"),children:"TEXT BUTTON"}),e.jsx(o,{disabled:!0,children:"DISABLED"})]}),e.jsx(t,{title:"Cards"}),e.jsxs("div",{className:"grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-12",children:[e.jsxs(n,{children:[e.jsx("h3",{className:"text-heading-3 font-medium text-foreground mb-4",children:"Card Example 1"}),e.jsx("p",{className:"text-body-sm text-foreground",children:"This is a card with some content. Cards are used to group related information and actions."})]}),e.jsxs(n,{children:[e.jsx("h3",{className:"text-heading-3 font-medium text-foreground mb-4",children:"Card Example 2"}),e.jsxs("div",{className:"space-y-2",children:[e.jsxs("div",{className:"flex justify-between text-body-sm",children:[e.jsx("span",{className:"text-muted-foreground",children:"Capacity:"}),e.jsx("span",{className:"text-foreground",children:"500g"})]}),e.jsxs("div",{className:"flex justify-between text-body-sm",children:[e.jsx("span",{className:"text-muted-foreground",children:"Type:"}),e.jsx("span",{className:"text-foreground",children:"Roaster"})]})]})]}),e.jsx(n,{className:"flex items-center justify-center min-h-[150px]",children:e.jsx(c,{onClick:()=>console.log("Add"),children:"ADD NEW CARD"})})]}),e.jsx(t,{title:"Form Components"}),e.jsx(p,{title:"Input Fields"}),e.jsxs("div",{className:"grid grid-cols-1 md:grid-cols-2 gap-6 mb-8",children:[e.jsx(m,{label:"MACHINE NAME",value:S,onChange:C,placeholder:"Enter machine name"}),e.jsx(m,{label:"CAPACITY",value:T,onChange:B,type:"number",placeholder:"500"})]}),e.jsx(p,{title:"Select Dropdowns"}),e.jsxs("div",{className:"grid grid-cols-1 md:grid-cols-2 gap-6 mb-8",children:[e.jsx(x,{label:"APPLICATION LANGUAGE",value:E,options:[{value:"english",label:"ENGLISH"},{value:"spanish",label:"ESPAÑOL"},{value:"french",label:"FRANÇAIS"}],onChange:A}),e.jsx(x,{label:"DATE FORMAT",value:D,options:[{value:"dd/mm/yyyy",label:"DD/MM/YYYY"},{value:"mm/dd/yyyy",label:"MM/DD/YYYY"},{value:"yyyy-mm-dd",label:"YYYY-MM-DD"}],onChange:P})]}),e.jsxs("div",{className:"flex gap-4 mt-8",children:[e.jsx(o,{onClick:()=>console.log("Save"),children:"SAVE CHANGES"}),e.jsx(i,{onClick:()=>console.log("Cancel"),children:"CANCEL"})]})]})}},d={render:()=>e.jsxs("div",{className:"px-[36px] py-8",children:[e.jsx(l,{title:"Color Palette",subtitle:"Rostoc brand colors and design tokens"}),e.jsx(t,{title:"Brand Colors"}),e.jsxs("div",{className:"grid grid-cols-2 md:grid-cols-3 gap-6 mb-12",children:[e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#e4410a] rounded mb-2"}),e.jsx("p",{className:"text-label text-foreground",children:"Tomato (Primary)"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#e4410a"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#f4f3dd] rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"Cream (Text)"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#f4f3dd"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#222222] rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"Coal (Background)"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#222222"})]})]}),e.jsx(t,{title:"Gray Scale"}),e.jsxs("div",{className:"grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-6 mb-12",children:[e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#222222] rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"gray/0"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#222222"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#343333] rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"gray/10"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#343333"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#484646] rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"gray/20"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#484646"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#646464] rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"gray/30"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#646464"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#c9c1c1] rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"gray/70"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#c9c1c1"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-[#ffffff] rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"gray/100"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"#ffffff"})]})]}),e.jsx(t,{title:"Semantic Colors"}),e.jsxs("div",{className:"grid grid-cols-2 md:grid-cols-3 gap-6",children:[e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-primary rounded mb-2"}),e.jsx("p",{className:"text-label text-foreground",children:"Primary"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"Brand Orange"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-secondary rounded mb-2"}),e.jsx("p",{className:"text-label text-foreground",children:"Secondary"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"Muted Gray"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-muted rounded mb-2"}),e.jsx("p",{className:"text-label text-foreground",children:"Muted"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"Subtle Background"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-card rounded mb-2 border border-border"}),e.jsx("p",{className:"text-label text-foreground",children:"Card"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"Card Background"})]}),e.jsxs("div",{children:[e.jsx("div",{className:"h-24 bg-destructive rounded mb-2"}),e.jsx("p",{className:"text-label text-foreground",children:"Destructive"}),e.jsx("p",{className:"text-body-sm text-muted-foreground",children:"Error State"})]})]})]})},r={render:()=>e.jsxs("div",{className:"px-[36px] py-8 space-y-8",children:[e.jsx(l,{title:"Typography",subtitle:"Font styles and text hierarchy from Figma"}),e.jsx(t,{title:"Title Styles (Space Grotesk)"}),e.jsxs("div",{className:"space-y-4",children:[e.jsxs("div",{children:[e.jsx("p",{className:"text-body-sm text-muted-foreground mb-2",children:"Title/Small - 20px/27px Medium"}),e.jsx("p",{className:"font-serif font-medium text-[20px] leading-[27px] uppercase text-foreground",children:"THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"})]}),e.jsxs("div",{children:[e.jsx("p",{className:"text-body-sm text-muted-foreground mb-2",children:"Title/XSmall - 13px/16px Medium Uppercase"}),e.jsx("p",{className:"font-serif font-medium text-[13px] leading-[16px] uppercase text-foreground",children:"THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"})]})]}),e.jsx(t,{title:"Body Styles (Instrument Sans)"}),e.jsxs("div",{className:"space-y-4",children:[e.jsxs("div",{children:[e.jsx("p",{className:"text-body-sm text-muted-foreground mb-2",children:"Body/XLarge - 28px/28px Regular"}),e.jsx("p",{className:"font-sans font-normal text-[28px] leading-[28px] text-foreground",children:"The quick brown fox jumps over the lazy dog"})]}),e.jsxs("div",{children:[e.jsx("p",{className:"text-body-sm text-muted-foreground mb-2",children:"Body/Large - 18px/18px Regular"}),e.jsx("p",{className:"font-sans font-normal text-[18px] leading-[18px] text-foreground",children:"The quick brown fox jumps over the lazy dog"})]}),e.jsxs("div",{children:[e.jsx("p",{className:"text-body-sm text-muted-foreground mb-2",children:"Body/Medium & Caption - 13px/16px Regular"}),e.jsx("p",{className:"font-sans font-normal text-[13px] leading-[16px] text-foreground",children:"The quick brown fox jumps over the lazy dog"})]})]}),e.jsx(t,{title:"Application Typography"}),e.jsxs("div",{className:"space-y-4",children:[e.jsx("h1",{className:"text-heading-1 text-foreground",children:"Heading 1 - 64px / 500"}),e.jsx("h2",{className:"text-heading-2 text-foreground",children:"Heading 2 - 36px / 500"}),e.jsx("h3",{className:"text-heading-3 text-foreground",children:"Heading 3 - 26px / 500"}),e.jsx("p",{className:"text-body text-foreground",children:"Body Text - 20px / 500 - This is the default body text size used throughout the application."}),e.jsx("p",{className:"text-body-sm text-foreground",children:"Body Small - 14px / 500 - Smaller body text for secondary information."}),e.jsx("p",{className:"text-label text-foreground",children:"LABEL - 13PX / 600 - UPPERCASE LABELS FOR FORM FIELDS"})]}),e.jsx(t,{title:"Font Families"}),e.jsxs("div",{className:"space-y-4",children:[e.jsxs("div",{children:[e.jsx("p",{className:"text-label text-foreground mb-2",children:"Space Grotesk (Titles)"}),e.jsx("p",{className:"font-serif text-body text-foreground",children:"Space Grotesk - Used for titles and headings in the Figma design system"})]}),e.jsxs("div",{children:[e.jsx("p",{className:"text-label text-foreground mb-2",children:"Instrument Sans (Body)"}),e.jsx("p",{className:"font-sans text-body text-foreground",children:"Instrument Sans - The primary font for body text and UI elements"})]}),e.jsxs("div",{children:[e.jsx("p",{className:"text-label text-foreground mb-2",children:"Monospace"}),e.jsx("p",{className:"font-mono text-body text-foreground",children:"JetBrains Mono - For code and technical information"})]})]})]})};var u,g,b;a.parameters={...a.parameters,docs:{...(u=a.parameters)==null?void 0:u.docs,source:{originalSource:`{
  render: () => {
    const [machineName, setMachineName] = useState('');
    const [capacity, setCapacity] = useState('');
    const [language, setLanguage] = useState('english');
    const [dateFormat, setDateFormat] = useState('dd/mm/yyyy');
    return <div className="px-[36px] py-8">
        <PageHeader title="Rostoc Design System" subtitle="A comprehensive example of all components" />

        <SectionHeader title="Buttons" />
        <div className="flex gap-4 mb-12">
          <PrimaryButton onClick={() => console.log('Primary clicked')}>
            PRIMARY BUTTON
          </PrimaryButton>
          <SecondaryButton onClick={() => console.log('Secondary clicked')}>
            SECONDARY BUTTON
          </SecondaryButton>
          <TextButton onClick={() => console.log('Text clicked')}>
            TEXT BUTTON
          </TextButton>
          <PrimaryButton disabled>DISABLED</PrimaryButton>
        </div>

        <SectionHeader title="Cards" />
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-12">
          <Card>
            <h3 className="text-heading-3 font-medium text-foreground mb-4">
              Card Example 1
            </h3>
            <p className="text-body-sm text-foreground">
              This is a card with some content. Cards are used to group related
              information and actions.
            </p>
          </Card>

          <Card>
            <h3 className="text-heading-3 font-medium text-foreground mb-4">
              Card Example 2
            </h3>
            <div className="space-y-2">
              <div className="flex justify-between text-body-sm">
                <span className="text-muted-foreground">Capacity:</span>
                <span className="text-foreground">500g</span>
              </div>
              <div className="flex justify-between text-body-sm">
                <span className="text-muted-foreground">Type:</span>
                <span className="text-foreground">Roaster</span>
              </div>
            </div>
          </Card>

          <Card className="flex items-center justify-center min-h-[150px]">
            <TextButton onClick={() => console.log('Add')}>
              ADD NEW CARD
            </TextButton>
          </Card>
        </div>

        <SectionHeader title="Form Components" />

        <SubsectionHeader title="Input Fields" />
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <Input label="MACHINE NAME" value={machineName} onChange={setMachineName} placeholder="Enter machine name" />
          <Input label="CAPACITY" value={capacity} onChange={setCapacity} type="number" placeholder="500" />
        </div>

        <SubsectionHeader title="Select Dropdowns" />
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <Select label="APPLICATION LANGUAGE" value={language} options={[{
          value: 'english',
          label: 'ENGLISH'
        }, {
          value: 'spanish',
          label: 'ESPAÑOL'
        }, {
          value: 'french',
          label: 'FRANÇAIS'
        }]} onChange={setLanguage} />
          <Select label="DATE FORMAT" value={dateFormat} options={[{
          value: 'dd/mm/yyyy',
          label: 'DD/MM/YYYY'
        }, {
          value: 'mm/dd/yyyy',
          label: 'MM/DD/YYYY'
        }, {
          value: 'yyyy-mm-dd',
          label: 'YYYY-MM-DD'
        }]} onChange={setDateFormat} />
        </div>

        <div className="flex gap-4 mt-8">
          <PrimaryButton onClick={() => console.log('Save')}>
            SAVE CHANGES
          </PrimaryButton>
          <SecondaryButton onClick={() => console.log('Cancel')}>
            CANCEL
          </SecondaryButton>
        </div>
      </div>;
  }
}`,...(b=(g=a.parameters)==null?void 0:g.docs)==null?void 0:b.source}}};var h,f,y;d.parameters={...d.parameters,docs:{...(h=d.parameters)==null?void 0:h.docs,source:{originalSource:`{
  render: () => <div className="px-[36px] py-8">
      <PageHeader title="Color Palette" subtitle="Rostoc brand colors and design tokens" />

      <SectionHeader title="Brand Colors" />
      <div className="grid grid-cols-2 md:grid-cols-3 gap-6 mb-12">
        <div>
          <div className="h-24 bg-[#e4410a] rounded mb-2"></div>
          <p className="text-label text-foreground">Tomato (Primary)</p>
          <p className="text-body-sm text-muted-foreground">#e4410a</p>
        </div>
        <div>
          <div className="h-24 bg-[#f4f3dd] rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">Cream (Text)</p>
          <p className="text-body-sm text-muted-foreground">#f4f3dd</p>
        </div>
        <div>
          <div className="h-24 bg-[#222222] rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">Coal (Background)</p>
          <p className="text-body-sm text-muted-foreground">#222222</p>
        </div>
      </div>

      <SectionHeader title="Gray Scale" />
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-6 mb-12">
        <div>
          <div className="h-24 bg-[#222222] rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">gray/0</p>
          <p className="text-body-sm text-muted-foreground">#222222</p>
        </div>
        <div>
          <div className="h-24 bg-[#343333] rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">gray/10</p>
          <p className="text-body-sm text-muted-foreground">#343333</p>
        </div>
        <div>
          <div className="h-24 bg-[#484646] rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">gray/20</p>
          <p className="text-body-sm text-muted-foreground">#484646</p>
        </div>
        <div>
          <div className="h-24 bg-[#646464] rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">gray/30</p>
          <p className="text-body-sm text-muted-foreground">#646464</p>
        </div>
        <div>
          <div className="h-24 bg-[#c9c1c1] rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">gray/70</p>
          <p className="text-body-sm text-muted-foreground">#c9c1c1</p>
        </div>
        <div>
          <div className="h-24 bg-[#ffffff] rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">gray/100</p>
          <p className="text-body-sm text-muted-foreground">#ffffff</p>
        </div>
      </div>

      <SectionHeader title="Semantic Colors" />
      <div className="grid grid-cols-2 md:grid-cols-3 gap-6">
        <div>
          <div className="h-24 bg-primary rounded mb-2"></div>
          <p className="text-label text-foreground">Primary</p>
          <p className="text-body-sm text-muted-foreground">Brand Orange</p>
        </div>
        <div>
          <div className="h-24 bg-secondary rounded mb-2"></div>
          <p className="text-label text-foreground">Secondary</p>
          <p className="text-body-sm text-muted-foreground">Muted Gray</p>
        </div>
        <div>
          <div className="h-24 bg-muted rounded mb-2"></div>
          <p className="text-label text-foreground">Muted</p>
          <p className="text-body-sm text-muted-foreground">
            Subtle Background
          </p>
        </div>
        <div>
          <div className="h-24 bg-card rounded mb-2 border border-border"></div>
          <p className="text-label text-foreground">Card</p>
          <p className="text-body-sm text-muted-foreground">Card Background</p>
        </div>
        <div>
          <div className="h-24 bg-destructive rounded mb-2"></div>
          <p className="text-label text-foreground">Destructive</p>
          <p className="text-body-sm text-muted-foreground">Error State</p>
        </div>
      </div>
    </div>
}`,...(y=(f=d.parameters)==null?void 0:f.docs)==null?void 0:y.source}}};var N,v,j;r.parameters={...r.parameters,docs:{...(N=r.parameters)==null?void 0:N.docs,source:{originalSource:`{
  render: () => <div className="px-[36px] py-8 space-y-8">
      <PageHeader title="Typography" subtitle="Font styles and text hierarchy from Figma" />

      <SectionHeader title="Title Styles (Space Grotesk)" />
      <div className="space-y-4">
        <div>
          <p className="text-body-sm text-muted-foreground mb-2">
            Title/Small - 20px/27px Medium
          </p>
          <p className="font-serif font-medium text-[20px] leading-[27px] uppercase text-foreground">
            THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG
          </p>
        </div>
        <div>
          <p className="text-body-sm text-muted-foreground mb-2">
            Title/XSmall - 13px/16px Medium Uppercase
          </p>
          <p className="font-serif font-medium text-[13px] leading-[16px] uppercase text-foreground">
            THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG
          </p>
        </div>
      </div>

      <SectionHeader title="Body Styles (Instrument Sans)" />
      <div className="space-y-4">
        <div>
          <p className="text-body-sm text-muted-foreground mb-2">
            Body/XLarge - 28px/28px Regular
          </p>
          <p className="font-sans font-normal text-[28px] leading-[28px] text-foreground">
            The quick brown fox jumps over the lazy dog
          </p>
        </div>
        <div>
          <p className="text-body-sm text-muted-foreground mb-2">
            Body/Large - 18px/18px Regular
          </p>
          <p className="font-sans font-normal text-[18px] leading-[18px] text-foreground">
            The quick brown fox jumps over the lazy dog
          </p>
        </div>
        <div>
          <p className="text-body-sm text-muted-foreground mb-2">
            Body/Medium & Caption - 13px/16px Regular
          </p>
          <p className="font-sans font-normal text-[13px] leading-[16px] text-foreground">
            The quick brown fox jumps over the lazy dog
          </p>
        </div>
      </div>

      <SectionHeader title="Application Typography" />
      <div className="space-y-4">
        <h1 className="text-heading-1 text-foreground">
          Heading 1 - 64px / 500
        </h1>
        <h2 className="text-heading-2 text-foreground">
          Heading 2 - 36px / 500
        </h2>
        <h3 className="text-heading-3 text-foreground">
          Heading 3 - 26px / 500
        </h3>
        <p className="text-body text-foreground">
          Body Text - 20px / 500 - This is the default body text size used
          throughout the application.
        </p>
        <p className="text-body-sm text-foreground">
          Body Small - 14px / 500 - Smaller body text for secondary information.
        </p>
        <p className="text-label text-foreground">
          LABEL - 13PX / 600 - UPPERCASE LABELS FOR FORM FIELDS
        </p>
      </div>

      <SectionHeader title="Font Families" />
      <div className="space-y-4">
        <div>
          <p className="text-label text-foreground mb-2">
            Space Grotesk (Titles)
          </p>
          <p className="font-serif text-body text-foreground">
            Space Grotesk - Used for titles and headings in the Figma design
            system
          </p>
        </div>
        <div>
          <p className="text-label text-foreground mb-2">
            Instrument Sans (Body)
          </p>
          <p className="font-sans text-body text-foreground">
            Instrument Sans - The primary font for body text and UI elements
          </p>
        </div>
        <div>
          <p className="text-label text-foreground mb-2">Monospace</p>
          <p className="font-mono text-body text-foreground">
            JetBrains Mono - For code and technical information
          </p>
        </div>
      </div>
    </div>
}`,...(j=(v=r.parameters)==null?void 0:v.docs)==null?void 0:j.source}}};const L=["CompleteExample","ColorPalette","Typography"];export{d as ColorPalette,a as CompleteExample,r as Typography,L as __namedExportsOrder,Y as default};
